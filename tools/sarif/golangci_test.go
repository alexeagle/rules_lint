package sarif

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestGolangciSarifNormalization(t *testing.T) {
	for _, tc := range []struct{ name, uri, want string }{
		{"sandbox", "../../../private/tmp/sandbox/execroot/_main/src/hello.go", "src/hello.go"},
		{"external", "file:///tmp/execroot/custom-repo/external/dep/pkg.go", "external/dep/pkg.go"},
		{"relative", "./src/hello.go", "src/hello.go"},
		{"parent", "../src/hello.go", "../src/hello.go"},
		{"absolute outside execroot", "/tmp/src/hello.go", "/tmp/src/hello.go"},
		{"empty", "", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			input := `{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"golangci-lint"}},"results":[{"message":{"text":"finding"},"locations":[{"physicalLocation":{"artifactLocation":{"uri":"` + tc.uri + `"},"region":{"startLine":7}}}]}]}]}`
			got, err := ToSarifJsonString("//src:hello", "AspectRulesLintGolangciLint", input)
			if err != nil {
				t.Fatal(err)
			}
			var doc struct {
				Runs []struct {
					Results []struct {
						Locations []struct {
							PhysicalLocation struct {
								ArtifactLocation struct{ URI string }
								Region           struct{ StartLine int }
							}
						}
					}
				}
			}
			if err := json.Unmarshal([]byte(got), &doc); err != nil {
				t.Fatal(err)
			}
			loc := doc.Runs[0].Results[0].Locations[0].PhysicalLocation
			if loc.ArtifactLocation.URI != tc.want {
				t.Errorf("URI = %q, want %q", loc.ArtifactLocation.URI, tc.want)
			}
			if loc.Region.StartLine != 7 || !strings.Contains(got, `"text":"finding"`) || !strings.Contains(got, `"name":"golangci-lint"`) {
				t.Errorf("report fields lost: %s", got)
			}
		})
	}
}

func TestGolangciSarifEmptyAndInvalid(t *testing.T) {
	for _, input := range []string{"", " \n"} {
		got, err := ToSarifJsonString("//:target", "AspectRulesLintGolangciLint", input)
		if err != nil || !json.Valid([]byte(got)) || !strings.Contains(got, `"runs":[]`) {
			t.Errorf("empty report: got %q, %v", got, err)
		}
	}
	for _, input := range []string{"broken", "{", "null", "[]"} {
		if _, err := ToSarifJsonString("//:target", "AspectRulesLintGolangciLint", input); err == nil {
			t.Errorf("invalid report %q accepted", input)
		}
	}
}
