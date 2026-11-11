/*
 * Copyright 2022 Aspect Build Systems, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package sarif

import (
	"encoding/json"
	"io"
	"strings"
	"testing"

	. "github.com/onsi/gomega"
)

// Decode only the SARIF fields asserted below. Keeping this in test code avoids
// pulling a diagnostic parser and its Protobuf types into the converter.
type sarifReport struct {
	Runs []struct {
		Tool struct {
			Driver struct {
				Name string `json:"name"`
			} `json:"driver"`
		} `json:"tool"`
		Results []struct {
			Level   string `json:"level"`
			Message struct {
				Text string `json:"text"`
			} `json:"message"`
			Locations []struct {
				PhysicalLocation struct {
					ArtifactLocation struct {
						URI string `json:"uri"`
					} `json:"artifactLocation"`
					Region struct {
						StartLine   int32 `json:"startLine"`
						StartColumn int32 `json:"startColumn"`
					} `json:"region"`
				} `json:"physicalLocation"`
			} `json:"locations"`
		} `json:"results"`
	} `json:"runs"`
}

func toSarifJson(sarifJsonString string) (report sarifReport, err error) {
	if sarifJsonString != "" {
		err = json.Unmarshal([]byte(sarifJsonString), &report)
	}
	return report, err
}

func TestSarif(t *testing.T) {
	t.Run("processes clang tidy output -> sarif correctly", func(t *testing.T) {
		g := NewGomegaWithT(t)
		stdOutReader, stdOutWriter := io.Pipe()
		stdOut := new(strings.Builder)
		go func() {
			io.Copy(stdOut, stdOutReader)
		}()

		sarifJsonString, _ := ToSarifJsonString("//speller/announce:announce", "AspectRulesLintClangTidy", clang_tidy_output)
		sarifJson, _ := toSarifJson(sarifJsonString)

		stdOutWriter.Close()
		stdOutReader.Close()

		g.Expect(len(sarifJson.Runs)).To(Equal(1))
		g.Expect(sarifJson.Runs[0].Tool.Driver.Name).To(Equal("ClangTidy"))
		g.Expect(len(sarifJson.Runs[0].Results)).To(Equal(2))
		g.Expect(sarifJson.Runs[0].Results[0].Message.Text).To(Equal("function is not thread safe [concurrency-mt-unsafe]"))
		g.Expect(sarifJson.Runs[0].Results[1].Message.Text).To(Equal("function is not thread safe [concurrency-mt-unsafe]"))
		g.Expect(sarifJson.Runs[0].Results[0].Locations[0].PhysicalLocation.ArtifactLocation.URI).To(Equal("speller/announce/announce.cc"))
		g.Expect(sarifJson.Runs[0].Results[1].Locations[0].PhysicalLocation.ArtifactLocation.URI).To(Equal("speller/announce/announce.cc"))
		g.Expect(sarifJson.Runs[0].Results[0].Locations[0].PhysicalLocation.Region.StartLine).To(Equal(int32(19)))
		g.Expect(sarifJson.Runs[0].Results[1].Locations[0].PhysicalLocation.Region.StartLine).To(Equal(int32(19)))
	})

	t.Run("processes taplo output -> sarif correctly", func(t *testing.T) {
		g := NewGomegaWithT(t)

		sarifJsonString, _ := ToSarifJsonString("//src:toml", "AspectRulesLintTaplo", taplo_output)
		sarifJson, _ := toSarifJson(sarifJsonString)

		g.Expect(len(sarifJson.Runs)).To(Equal(1))
		g.Expect(sarifJson.Runs[0].Tool.Driver.Name).To(Equal("Taplo"))
		g.Expect(len(sarifJson.Runs[0].Results)).To(Equal(2))
		g.Expect(sarifJson.Runs[0].Results[0].Message.Text).To(Equal("invalid TOML"))
		g.Expect(sarifJson.Runs[0].Results[1].Message.Text).To(Equal("conflicting keys"))
		g.Expect(sarifJson.Runs[0].Results[0].Locations[0].PhysicalLocation.ArtifactLocation.URI).To(Equal("src/invalid.toml"))
		g.Expect(sarifJson.Runs[0].Results[1].Locations[0].PhysicalLocation.ArtifactLocation.URI).To(Equal("src/bad.toml"))
		g.Expect(sarifJson.Runs[0].Results[0].Locations[0].PhysicalLocation.Region.StartLine).To(Equal(int32(1)))
		g.Expect(sarifJson.Runs[0].Results[1].Locations[0].PhysicalLocation.Region.StartLine).To(Equal(int32(3)))
		g.Expect(sarifJson.Runs[0].Results[0].Locations[0].PhysicalLocation.Region.StartColumn).To(Equal(int32(5)))
		// Assert SARIF's one-based column directly, without RDF normalization.
		g.Expect(sarifJson.Runs[0].Results[1].Locations[0].PhysicalLocation.Region.StartColumn).To(Equal(int32(1)))
	})

	t.Run("processes pydoclint output -> sarif correctly", func(t *testing.T) {
		g := NewGomegaWithT(t)

		sarifJsonString, _ := ToSarifJsonString("//src:missing_doc_arg", "AspectRulesLintPydoclint", pydoclint_output)
		sarifJson, _ := toSarifJson(sarifJsonString)

		g.Expect(len(sarifJson.Runs)).To(Equal(1))
		g.Expect(sarifJson.Runs[0].Tool.Driver.Name).To(Equal("Pydoclint"))
		g.Expect(len(sarifJson.Runs[0].Results)).To(Equal(2))
		g.Expect(sarifJson.Runs[0].Results[0].Message.Text).To(Equal("DOC101: Function `documented_add`: Docstring contains fewer arguments than in function signature."))
		g.Expect(sarifJson.Runs[0].Results[1].Message.Text).To(ContainSubstring("DOC103:"))
		g.Expect(sarifJson.Runs[0].Results[0].Locations[0].PhysicalLocation.ArtifactLocation.URI).To(Equal("src/missing_doc_arg.py"))
		g.Expect(sarifJson.Runs[0].Results[0].Locations[0].PhysicalLocation.Region.StartLine).To(Equal(int32(4)))
	})
	t.Run("processes cppcheck text output -> sarif correctly", func(t *testing.T) {
		g := NewGomegaWithT(t)

		sarifJsonString, err := ToSarifJsonString("//src:hello_cc", "AspectRulesLintCppCheck", cppcheck_output)
		g.Expect(err).ToNot(HaveOccurred())

		sarifJson, err := toSarifJson(sarifJsonString)
		g.Expect(err).ToNot(HaveOccurred())
		g.Expect(len(sarifJson.Runs)).To(Equal(1))

		run := sarifJson.Runs[0]
		g.Expect(run.Tool.Driver.Name).To(Equal("CppCheck"))

		// the progress lines and the location-less checkersReport entry contribute no results
		g.Expect(len(run.Results)).To(Equal(6))
		for _, result := range run.Results {
			g.Expect(result.Message.Text).ToNot(ContainSubstring("checkersReport"))
			g.Expect(result.Message.Text).ToNot(ContainSubstring("Checking "))
		}

		// --report-type makes cppcheck print the classification in place of the severity and the
		// guideline in place of the id, so a Required violation outranks its style severity
		guideline := run.Results[0]
		g.Expect(guideline.Level).To(Equal("error"))
		// the tag rides along in the message rather than being set as ruleId: reviewdog writes a
		// ruleId as a bare `<id>`, which GitHub's markdown sanitizer strips when it parses as an
		// HTML tag name
		g.Expect(guideline.Message.Text).To(Equal("A public base class should declare a protected non-virtual destructor. [Required 15.0.1]"))
		g.Expect(guideline.Locations[0].PhysicalLocation.ArtifactLocation.URI).To(Equal("src/base.h"))
		g.Expect(guideline.Locations[0].PhysicalLocation.Region.StartLine).To(Equal(int32(38)))
		g.Expect(guideline.Locations[0].PhysicalLocation.Region.StartColumn).To(Equal(int32(19)))

		// a finding cppcheck did not map to a guideline keeps its severity and id
		uninit := run.Results[1]
		g.Expect(uninit.Level).To(Equal("warning"))
		g.Expect(uninit.Message.Text).To(HaveSuffix(" [warning uninitMemberVar]"))
		// sandbox-absolute paths are made workspace-relative, as for the other text-scraped linters
		g.Expect(uninit.Locations[0].PhysicalLocation.ArtifactLocation.URI).To(Equal("src/widget.h"))

		g.Expect(run.Results[2].Level).To(Equal("error"))

		// a guideline with no classification keeps the plain severity, which stays a note. The
		// severity is consumed off the front of the line, so it shows up only in the tag.
		g.Expect(run.Results[3].Level).To(Equal("note"))
		g.Expect(run.Results[3].Message.Text).To(Equal("Consider using std::find_if algorithm instead of a raw loop. [performance 6.9.2]"))

		g.Expect(run.Results[4].Level).To(Equal("warning"))
		g.Expect(run.Results[4].Message.Text).To(HaveSuffix(" [Advisory 15.1.4]"))

		// an unenumerated classification is still reported, at note level, keeping its leading token
		g.Expect(run.Results[5].Level).To(Equal("note"))
		g.Expect(run.Results[5].Message.Text).To(Equal("L1: Do not use a bare pointer here. [L1 certDemo-MEM50]"))
	})

	t.Run("processes ktlint output -> sarif correctly", func(t *testing.T) {
		g := NewGomegaWithT(t)

		sarifJsonString, _ := ToSarifJsonString("//src:hello_kt", "AspectRulesLintKTLint", ktlint_output)
		sarifJson, _ := toSarifJson(sarifJsonString)

		g.Expect(len(sarifJson.Runs)).To(Equal(1))
		g.Expect(sarifJson.Runs[0].Tool.Driver.Name).To(Equal("KTLint"))
		g.Expect(len(sarifJson.Runs[0].Results)).To(Equal(2))
		g.Expect(sarifJson.Runs[0].Results[0].Message.Text).To(Equal("File name 'hello.kt' should conform PascalCase (standard:filename)"))
		g.Expect(sarifJson.Runs[0].Results[1].Message.Text).To(Equal("Wildcard import (standard:no-wildcard-imports)"))
		g.Expect(sarifJson.Runs[0].Results[0].Locations[0].PhysicalLocation.ArtifactLocation.URI).To(Equal("src/hello.kt"))
		g.Expect(sarifJson.Runs[0].Results[0].Locations[0].PhysicalLocation.Region.StartLine).To(Equal(int32(1)))
		g.Expect(sarifJson.Runs[0].Results[1].Locations[0].PhysicalLocation.Region.StartLine).To(Equal(int32(2)))
	})

	t.Run("processes scalafix diff output -> sarif correctly", func(t *testing.T) {
		g := NewGomegaWithT(t)

		diff := `--- /private/var/tmp/_bazel_foo/execroot/_main/src/semantic_test.scala
+++ <expected fix>
@@ -2,8 +2,8 @@
-import scala.util.Try
+import scala.util.Try
`

		sarifJsonString, _ := ToSarifJsonString("//src:semantic_test", "AspectRulesLintScalafix", diff)
		sarifJson, _ := toSarifJson(sarifJsonString)

		g.Expect(len(sarifJson.Runs)).To(Equal(1))
		g.Expect(len(sarifJson.Runs[0].Results)).To(Equal(1))
		g.Expect(sarifJson.Runs[0].Results[0].Message.Text).To(Equal("Scalafix rewrite suggested"))
		g.Expect(sarifJson.Runs[0].Results[0].Locations[0].PhysicalLocation.ArtifactLocation.URI).To(Equal("src/semantic_test.scala"))
		g.Expect(sarifJson.Runs[0].Results[0].Locations[0].PhysicalLocation.Region.StartLine).To(Equal(int32(2)))
	})

	t.Run("determineRelativePath: converts Windows path separators to URI separators", func(t *testing.T) {
		g := NewGomegaWithT(t)

		// These run on every platform, so they exercise the conversion on Linux CI too.
		g.Expect(determineRelativePath(`src\file.ts`, "//src:ts")).To(Equal("src/file.ts"))
		g.Expect(determineRelativePath(`foo\bar\baz`, "//foo/bar:baz")).To(Equal("foo/bar/baz"))
		g.Expect(determineRelativePath(`src\file.ts`, "")).To(Equal("src/file.ts"))

		// A POSIX path is already a valid URI path and is returned untouched.
		g.Expect(determineRelativePath("src/file.ts", "//src:ts")).To(Equal("src/file.ts"))
		g.Expect(determineRelativePath("foo/bar/baz", "//foo/bar:baz")).To(Equal("foo/bar/baz"))
	})

	t.Run("determineRelativePath: returns relative paths untouched", func(t *testing.T) {
		g := NewGomegaWithT(t)

		// incomplete bazel label
		g.Expect(determineRelativePath("foo", "")).To(Equal("foo"))
		g.Expect(determineRelativePath("foo/bar/baz", "")).To(Equal("foo/bar/baz"))
		g.Expect(determineRelativePath("foo", "bar")).To(Equal("foo"))
		g.Expect(determineRelativePath("foo/bar/baz", "bar")).To(Equal("foo/bar/baz"))
		g.Expect(determineRelativePath("foo", "/bar")).To(Equal("foo"))
		g.Expect(determineRelativePath("foo/bar/baz", "/bar")).To(Equal("foo/bar/baz"))

		// normal bazel labels
		g.Expect(determineRelativePath("foo", "//foo")).To(Equal("foo"))
		g.Expect(determineRelativePath("foo/bar/baz", "//foo")).To(Equal("foo/bar/baz"))
		g.Expect(determineRelativePath("foo", "//foo:bar")).To(Equal("foo"))
		g.Expect(determineRelativePath("foo/bar/baz", "//foo:bar")).To(Equal("foo/bar/baz"))
		g.Expect(determineRelativePath("foo", "//foo/bar")).To(Equal("foo"))
		g.Expect(determineRelativePath("foo/bar/baz", "//foo/bar")).To(Equal("foo/bar/baz"))
		g.Expect(determineRelativePath("foo", "//foo/bar:baz")).To(Equal("foo"))
		g.Expect(determineRelativePath("foo/bar/baz", "//foo/bar:baz")).To(Equal("foo/bar/baz"))
	})

	t.Run("determineRelativePath: returns absolute paths as relative paths", func(t *testing.T) {
		g := NewGomegaWithT(t)

		// real examples
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/769/execroot/_main/speller/lookup/lookup-test.cc", "//speller/lookup:lookup")).To(Equal("speller/lookup/lookup-test.cc"))
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/780/execroot/_main/speller/data_driven_tests/lookup-datatest.cc", "//speller/data_driven_tests:test-002")).To(Equal("speller/data_driven_tests/lookup-datatest.cc"))
		g.Expect(determineRelativePath("/private/var/tmp/_bazel_jesse/93d7e699c5e2019d94351d19b00be5a3/sandbox/darwin-sandbox/249/execroot/_main/speller/announce/announce.cc", "//speller/announce:announce")).To(Equal("speller/announce/announce.cc"))

		// execroot in label
		g.Expect(determineRelativePath("/some_path/sandbox/linux-sandbox/769/execroot/_main/execroot/foo/bar.baz", "//execroot:foo")).To(Equal("execroot/foo/bar.baz"))
		g.Expect(determineRelativePath("/some_path/sandbox/linux-sandbox/769/execroot/_main/execroot/foo/bar.baz", "//:foo")).To(Equal("execroot/foo/bar.baz"))
		g.Expect(determineRelativePath("/some_path/sandbox/linux-sandbox/769/execroot/_main/execroot/foo/bar.baz", "//execroot/foo:foo")).To(Equal("execroot/foo/bar.baz"))
		g.Expect(determineRelativePath("/some_path/sandbox/linux-sandbox/769/execroot/_main/foo/execroot/bar.baz", "//foo/execroot:execroot")).To(Equal("foo/execroot/bar.baz"))

		// Short labels
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/769/execroot/_main/speller/lookup/lookup-test.cc", "//speller/lookup")).To(Equal("speller/lookup/lookup-test.cc"))
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/780/execroot/_main/speller/data_driven_tests/lookup-datatest.cc", "//speller/data_driven_tests")).To(Equal("speller/data_driven_tests/lookup-datatest.cc"))
		g.Expect(determineRelativePath("/private/var/tmp/_bazel_jesse/93d7e699c5e2019d94351d19b00be5a3/sandbox/darwin-sandbox/249/execroot/_main/speller/announce/announce.cc", "//speller/announce")).To(Equal("speller/announce/announce.cc"))
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/769/execroot/_main/speller/lookup/lookup-test.cc", "//speller")).To(Equal("speller/lookup/lookup-test.cc"))
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/780/execroot/_main/speller/data_driven_tests/lookup-datatest.cc", "//speller")).To(Equal("speller/data_driven_tests/lookup-datatest.cc"))
		g.Expect(determineRelativePath("/private/var/tmp/_bazel_jesse/93d7e699c5e2019d94351d19b00be5a3/sandbox/darwin-sandbox/249/execroot/_main/speller/announce/announce.cc", "//speller")).To(Equal("speller/announce/announce.cc"))
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/769/execroot/_main/speller/lookup/lookup-test.cc", "//:lookup")).To(Equal("speller/lookup/lookup-test.cc"))
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/780/execroot/_main/speller/data_driven_tests/lookup-datatest.cc", "//:data_driven_tests")).To(Equal("speller/data_driven_tests/lookup-datatest.cc"))
		g.Expect(determineRelativePath("/private/var/tmp/_bazel_jesse/93d7e699c5e2019d94351d19b00be5a3/sandbox/darwin-sandbox/249/execroot/_main/speller/announce/announce.cc", "//:announce")).To(Equal("speller/announce/announce.cc"))

		// Windows path, with a drive letter instead of a leading slash
		g.Expect(determineRelativePath("c:/private/var/tmp/_bazel_jesse/93d7e699c5e2019d94351d19b00be5a3/sandbox/darwin-sandbox/249/execroot/_main/speller/announce/announce.cc", "//speller/announce:announce")).To(Equal("speller/announce/announce.cc"))
		g.Expect(determineRelativePath(`c:\private\var\tmp\_bazel_jesse\93d7e699c5e2019d94351d19b00be5a3\sandbox\darwin-sandbox\249\execroot\_main\speller\announce\announce.cc`, "//speller/announce:announce")).To(Equal("speller/announce/announce.cc"))
		g.Expect(determineRelativePath("C:/users/jesse/_bazel/abc123/execroot/_main/speller/announce/announce.cc", "//:announce")).To(Equal("speller/announce/announce.cc"))
		g.Expect(determineRelativePath(`C:\users\jesse\_bazel\abc123\execroot\_main\speller\announce\announce.cc`, "//:announce")).To(Equal("speller/announce/announce.cc"))
	})

	t.Run("determineRelativePath: returns absolute paths on regex or label error", func(t *testing.T) {
		g := NewGomegaWithT(t)

		// non bazel absolute path
		g.Expect(determineRelativePath("/some/path/foo/bar.baz", "//foo:foo")).To(Equal("/some/path/foo/bar.baz"))
		g.Expect(determineRelativePath("/some/path/foo/bar.baz", "//foo")).To(Equal("/some/path/foo/bar.baz"))

		// invalid labels
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/769/execroot/_main/speller/lookup/lookup-test.cc", "")).To(Equal("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/769/execroot/_main/speller/lookup/lookup-test.cc"))
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/780/execroot/_main/speller/data_driven_tests/lookup-datatest.cc", "")).To(Equal("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/780/execroot/_main/speller/data_driven_tests/lookup-datatest.cc"))
		g.Expect(determineRelativePath("/private/var/tmp/_bazel_jesse/93d7e699c5e2019d94351d19b00be5a3/sandbox/darwin-sandbox/249/execroot/_main/speller/announce/announce.cc", "")).To(Equal("/private/var/tmp/_bazel_jesse/93d7e699c5e2019d94351d19b00be5a3/sandbox/darwin-sandbox/249/execroot/_main/speller/announce/announce.cc"))
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/769/execroot/_main/speller/lookup/lookup-test.cc", "//foo")).To(Equal("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/769/execroot/_main/speller/lookup/lookup-test.cc"))
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/780/execroot/_main/speller/data_driven_tests/lookup-datatest.cc", "//foo")).To(Equal("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/780/execroot/_main/speller/data_driven_tests/lookup-datatest.cc"))
		g.Expect(determineRelativePath("/private/var/tmp/_bazel_jesse/93d7e699c5e2019d94351d19b00be5a3/sandbox/darwin-sandbox/249/execroot/_main/speller/announce/announce.cc", "//foo")).To(Equal("/private/var/tmp/_bazel_jesse/93d7e699c5e2019d94351d19b00be5a3/sandbox/darwin-sandbox/249/execroot/_main/speller/announce/announce.cc"))
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/769/execroot/_main/speller/lookup/lookup-test.cc", "speller/lookup")).To(Equal("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/769/execroot/_main/speller/lookup/lookup-test.cc"))
		g.Expect(determineRelativePath("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/780/execroot/_main/speller/data_driven_tests/lookup-datatest.cc", "speller/data_driven_tests")).To(Equal("/mnt/ephemeral/output/bazel-examples/__main__/sandbox/linux-sandbox/780/execroot/_main/speller/data_driven_tests/lookup-datatest.cc"))
		g.Expect(determineRelativePath("/private/var/tmp/_bazel_jesse/93d7e699c5e2019d94351d19b00be5a3/sandbox/darwin-sandbox/249/execroot/_main/speller/announce/announce.cc", "speller/announce")).To(Equal("/private/var/tmp/_bazel_jesse/93d7e699c5e2019d94351d19b00be5a3/sandbox/darwin-sandbox/249/execroot/_main/speller/announce/announce.cc"))
	})
}
