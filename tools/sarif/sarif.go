/*
 * Copyright 2024 Aspect Build Systems, Inc.
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
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"regexp"
	"strconv"
	"strings"

	"github.com/reviewdog/errorformat"
	"github.com/reviewdog/errorformat/fmts"
	"github.com/reviewdog/errorformat/writer"
)

func mnemonicPrettyName(mnemonic string) string {
	return strings.Replace(mnemonic, "AspectRulesLint", "", 1)
}

func ToSarifJsonString(label string, mnemonic string, report string) (sarifJsonString string, err error) {
	if mnemonic == "AspectRulesLintGolangciLint" {
		return normalizeGolangciSarif(report)
	}
	regex := regexp.MustCompile(`^{\s+"\$schema":.+sarif`)
	// If it's already in SARIF format, just return it
	if regex.Match([]byte(report)) {
		return report, nil
	}

	if len(mnemonic) == 0 {
		return "", fmt.Errorf("Undefined linter mnemonic for target %s\n", label)
	}

	var fm []string

	// NB: Switch is on the MNEMONIC declared in rules_lint
	// Helpful link for building custom fm strings: https://vimdoc.sourceforge.net/htmldoc/quickfix.html#errorformat
	switch mnemonic {
	case "AspectRulesLintBuildifier":
		fm = []string{
			`%f:%l:%c: %m`,
			`%f:%l: %m`,
		}
	case "AspectRulesLintESLint":
		fm = fmts.DefinedFmts()["eslint-compact"].Errorformat
	case "AspectRulesLintFlake8":
		fm = fmts.DefinedFmts()["flake8"].Errorformat
	case "AspectRulesLintPMD":
		// TODO: upstream to https://github.com/reviewdog/errorformat/issues/62
		fm = []string{`%f:%l:\\t%m`}
	case "AspectRulesLintPylint":
		fm = []string{`%f:%l:%c: %m`}
	case "AspectRulesLintPydoclint":
		fm = []string{`%f:%l: %m`}
	case "AspectRulesLintRuff":
		fm = []string{
			// %E forces a multiline error severity message. There is no forced single line error message
			`%E%f:%l:%c: %m`,
			// End the multiline error message on the next line and ignore said line
			`%-Z%r`,
		}
	case "AspectRulesLintBuf":
		fm = []string{
			`%E--buf-plugin_out: %f:%l:%c:%m`,
			`%-Z%r`,
		}
	case "AspectRulesLintVale":
		fm = []string{`%f:%l:%c:%m`}
	case "AspectRulesLintCppCheck":
		// Keyed to the --template the cppcheck aspect pins. Order matters: errorformat takes
		// the first matching pattern, so the ignore patterns have to precede what they would
		// otherwise fall into.
		fm = []string{
			// run metadata carries no location, e.g. `nofile:0:0: information: Active checkers: ...`
			`%-Gnofile:%.%#`,
			`%E%f:%l:%c: error: %m`,
			// --report-type prints the coding-standard classification in place of the severity
			`%E%f:%l:%c: Mandatory: %m`,
			`%E%f:%l:%c: Required: %m`,
			`%W%f:%l:%c: warning: %m`,
			`%W%f:%l:%c: Advisory: %m`,
			`%I%f:%l:%c: style: %m`,
			`%I%f:%l:%c: performance: %m`,
			`%I%f:%l:%c: portability: %m`,
			`%I%f:%l:%c: information: %m`,
			`%I%f:%l:%c: debug: %m`,
			// a classification this list does not enumerate still yields a finding. Its leading
			// token stays in the message, since errorformat cannot both match and discard it.
			`%I%f:%l:%c: %m`,
			`%-G%.%#`,
		}
	case "AspectRulesLintClangTidy":
		fm = []string{
			`%f:%l:%c: %trror: %m`,
			`%f:%l:%c: %tarning: %m`,
			`%-G%m`, // this will ignore any lines that do not match the above 2 lines
			// TODO: Do the other fm's need this ^
		}
	case "AspectRulesLintShellCheck":
		fm = []string{
			`%AIn\ %f\ line\ %l:`,
			`%C%.%#(%trror):\ %m%Z`,
			`%C%.%#(%tarning):\ %m%Z`,
			`%C%.%#(%tnfo):\ %m%Z`,
			`%C%.%#`,
		}
	case "AspectRulesLintStylelint":
		fm = []string{
			`%f: line %l\, col %c\, %trror - %m`,
			`%f: line %l\, col %c\, %tarning - %m`,
		}
	case "AspectRulesLintYamllint":
		fm = []string{
			`%E%f:%l:%c: [error] %m`,
			`%W%f:%l:%c: [warning] %m`,
			`%I%f:%l:%c: [info] %m`,
		}
	case "AspectRulesLintQmllint":
		fm = []string{
			`%EError: %f:%l:%c: %m`,
			`%WWarning: %f:%l:%c: %m`,
			`%IInfo: %f:%l:%c: %m`,
			`%-G%.%#`,
		}
	case "AspectRulesLintKTLint":
		// ktlint --relative text output: `path:line:col: message (rule)`.
		fm = []string{`%f:%l:%c: %m`}
	case "AspectRulesLintKeepSorted":
		fm = []string{`%f:%l:%e:%m`}
	case "AspectRulesLintTy":
		fm = []string{
			`%Eerror%m`,
			`%C\\ %#-->\\ %f:%l:%c`,
			`%-G%.%#`,
		}
	case "AspectRulesLintRuboCop", "AspectRulesLintStandardRB":
		return rubocopJsonToSarif(label, mnemonic, report)
	case "AspectRulesLintScalafix":
		fm = []string{
			`%f:%l:%c: %trror: %m`,
			`%f:%l:%c: %tarning: %m`,
			`%-G%m`, // ignore any lines that do not match the above patterns
		}
	case "AspectRulesLintTaplo":
		fm = []string{
			`%Eerror: %m`,
			`%C%.%# %f:%l:%c`,
			`%-G%.%#`,
		}
	default:
		return "", fmt.Errorf("No format string for linter mnemonic %s from target %s\n", mnemonic, label)
	}

	if len(fm) == 0 {
		return "", nil
	}
	efm, err := errorformat.NewErrorformat(fm)
	if err != nil {
		return "", err
	}

	var jsonBuffer bytes.Buffer
	var jsonWriter writer.Writer

	var sarifOpt writer.SarifOption
	sarifOpt.ToolName = mnemonicPrettyName(mnemonic)
	jsonWriter, err = writer.NewSarif(&jsonBuffer, sarifOpt)
	if err != nil {
		return "", err
	}

	if jsonWriter, ok := jsonWriter.(writer.BufWriter); ok {
		defer func() {
			if err := jsonWriter.Flush(); err != nil {
				log.Println(err)
			}

			sarifJsonString = jsonBuffer.String()
		}()
	}

	s := efm.NewScanner(strings.NewReader(report))
	for s.Scan() {
		entry := s.Entry()
		if entry.Filename != "" && entry.Text != "" {
			entry.Filename = determineRelativePath(entry.Filename, label)
			if err := jsonWriter.Write(entry); err != nil {
				return "", err
			}
		}
	}

	if mnemonic == "AspectRulesLintScalafix" {
		for _, entry := range scalafixDiffEntries(report) {
			entry.Filename = determineRelativePath(entry.Filename, label)
			if err := jsonWriter.Write(entry); err != nil {
				return "", err
			}
		}
	}

	return sarifJsonString, nil
}

// rubocopJsonToSarif converts a RuboCop/StandardRB JSON report (--format json) to SARIF.
// Both linters share the same JSON schema.
func rubocopJsonToSarif(label, mnemonic, report string) (sarifJsonString string, err error) {
	var rb struct {
		Files []struct {
			Path     string `json:"path"`
			Offenses []struct {
				Severity string `json:"severity"`
				Message  string `json:"message"`
				CopName  string `json:"cop_name"`
				Location struct {
					Line   int `json:"line"`
					Column int `json:"column"`
				} `json:"location"`
			} `json:"offenses"`
		} `json:"files"`
	}
	if err = json.Unmarshal([]byte(report), &rb); err != nil {
		return "", fmt.Errorf("failed to parse RuboCop JSON: %w", err)
	}

	var buf bytes.Buffer
	var jw writer.Writer
	jw, err = writer.NewSarif(&buf, writer.SarifOption{ToolName: mnemonicPrettyName(mnemonic)})
	if err != nil {
		return "", err
	}

	if bw, ok := jw.(writer.BufWriter); ok {
		defer func() {
			if fErr := bw.Flush(); fErr != nil {
				log.Println(fErr)
			}
			sarifJsonString = buf.String()
		}()
	}

	for _, f := range rb.Files {
		for _, o := range f.Offenses {
			t := rune('W')
			switch o.Severity {
			case "error", "fatal":
				t = 'E'
			case "convention", "refactor", "info":
				t = 'I'
			}
			entry := &errorformat.Entry{
				Filename: determineRelativePath(f.Path, label),
				Lnum:     o.Location.Line,
				Col:      o.Location.Column,
				Type:     t,
				Text:     o.CopName + ": " + o.Message,
			}
			if err = jw.Write(entry); err != nil {
				return "", err
			}
		}
	}

	return sarifJsonString, nil
}

// Matches an absolute path once separators have been normalised to slashes:
// either a POSIX path ("/foo") or a Windows drive-letter path ("C:/foo").
// filepath.IsAbs cannot be used here because it only recognises the host's
// convention, which would make the result depend on the platform running the linter.
var absolutePathRe = regexp.MustCompile(`^(?:/|[a-zA-Z]:/)`)

// We expect relative paths when processing lint output and therefore need to convert any absolute paths.
// Assumptions we make when determining the relative paths:
//   - The linter is running on the host, so the path will have an 'execroot' segment
//   - We only lint source files, so there is no 'bazel-bin/<platform>/bin' segment
func determineRelativePath(path string, label string) string {
	// A SARIF artifactLocation.uri is a URI, so it always uses forward slashes.
	path = strings.ReplaceAll(path, `\`, "/")

	if !absolutePathRe.MatchString(path) || !strings.HasPrefix(label, "//") {
		return path
	}

	bazel_package := strings.Split(label[2:], ":")[0]

	// https://regex101.com/r/uMbVHP/1
	re := regexp.MustCompile(`\/execroot\/[^\/]+\/(.*)$`)
	if bazel_package != "" {
		re = regexp.MustCompile(`\/execroot\/[^\/]+\/(` + bazel_package + `\/.*)$`)
	}
	relative_path := re.FindSubmatch([]byte(path))

	if len(relative_path) == 2 {
		return string(relative_path[1])
	}

	return path
}

func scalafixDiffEntries(report string) []*errorformat.Entry {
	var entries []*errorformat.Entry
	var currentFile string
	hunkRe := regexp.MustCompile(`^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@`)

	for _, line := range strings.Split(report, "\n") {
		if strings.HasPrefix(line, "--- ") {
			path := strings.TrimSpace(strings.TrimPrefix(line, "--- "))
			if path == "" {
				currentFile = ""
				continue
			}
			currentFile = path
			continue
		}
		if strings.HasPrefix(line, "+++ ") {
			if currentFile == "" {
				path := strings.TrimSpace(strings.TrimPrefix(line, "+++ "))
				if path != "" && path != "<expected fix>" {
					currentFile = path
				}
			}
			continue
		}

		match := hunkRe.FindStringSubmatch(line)
		if len(match) == 2 && currentFile != "" {
			start, err := strconv.Atoi(match[1])
			if err != nil {
				continue
			}
			entries = append(entries, &errorformat.Entry{
				Filename: currentFile,
				Lnum:     start,
				Col:      1,
				Text:     "Scalafix rewrite suggested",
				Type:     'W',
				Valid:    true,
			})
		}
	}

	return entries
}

// normalizeGolangciSarif preserves the report's fields while making result URIs
// portable across Bazel execroots. Invalid JSON must fail, not hide findings.
func normalizeGolangciSarif(report string) (string, error) {
	if strings.TrimSpace(report) == "" {
		return `{"version":"2.1.0","$schema":"https://json.schemastore.org/sarif-2.1.0.json","runs":[]}`, nil
	}
	var doc map[string]json.RawMessage
	if err := json.Unmarshal([]byte(report), &doc); err != nil {
		return "", fmt.Errorf("invalid golangci-lint SARIF: %w", err)
	}
	if doc == nil {
		return "", fmt.Errorf("invalid golangci-lint SARIF: expected an object")
	}
	// Walk artifactLocation objects, including related locations, without
	// dropping report fields.
	var walk func(json.RawMessage) (json.RawMessage, error)
	walk = func(raw json.RawMessage) (json.RawMessage, error) {
		trimmed := bytes.TrimSpace(raw)
		if len(trimmed) == 0 {
			return raw, nil
		}
		if trimmed[0] == '{' {
			var obj map[string]json.RawMessage
			if err := json.Unmarshal(raw, &obj); err != nil {
				return nil, err
			}
			for key, value := range obj {
				if key == "artifactLocation" {
					var art map[string]json.RawMessage
					if err := json.Unmarshal(value, &art); err != nil {
						return nil, err
					}
					if uriRaw, ok := art["uri"]; ok {
						var uri string
						if err := json.Unmarshal(uriRaw, &uri); err != nil {
							return nil, err
						}
						uri = strings.TrimPrefix(uri, "file://")
						if i := strings.Index(uri, "/execroot/"); i >= 0 {
							rest := uri[i+len("/execroot/"):]
							uri = rest
							if j := strings.IndexByte(rest, '/'); j >= 0 {
								uri = rest[j+1:]
							}
						} else {
							uri = strings.TrimPrefix(uri, "./")
						}
						art["uri"], _ = json.Marshal(uri)
					}
					obj[key], _ = json.Marshal(art)
				} else {
					v, err := walk(value)
					if err != nil {
						return nil, err
					}
					obj[key] = v
				}
			}
			return json.Marshal(obj)
		}
		if trimmed[0] == '[' {
			var arr []json.RawMessage
			if err := json.Unmarshal(raw, &arr); err != nil {
				return nil, err
			}
			for i, value := range arr {
				v, err := walk(value)
				if err != nil {
					return nil, err
				}
				arr[i] = v
			}
			return json.Marshal(arr)
		}
		return raw, nil
	}
	normalized, err := walk(json.RawMessage(report))
	if err != nil {
		return "", fmt.Errorf("invalid golangci-lint SARIF: %w", err)
	}
	return string(normalized), nil
}
