package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"golang.org/x/tools/go/packages"
)

// TestRunResolvesAndInjects exercises the two behaviors that distinguish the
// static driver from a naive port of the rules_go gopackagesdriver:
//
//  1. stdlib ExportFile injection: a Standard:true package with an empty
//     ExportFile gets one synthesized from GOPACKAGESDRIVER_STDLIB_PKG_DIR.
//  2. roots come from GOPACKAGESDRIVER_ROOTS (env), not os.Args.
//
// It also confirms the __BAZEL_EXECROOT__ placeholder is resolved and that the
// injected (already absolute) stdlib ExportFile survives ResolvePaths untouched.
func TestRunResolvesAndInjects(t *testing.T) {
	tmp := t.TempDir()

	// Work tree where resolved source files live so go/parser can read them
	// during ResolveImports. Both the first-party source and the stdlib source
	// must exist on disk at their resolved paths.
	execroot := filepath.Join(tmp, "execroot")
	workspace := filepath.Join(tmp, "workspace")
	outputBase := filepath.Join(tmp, "outputbase")
	jsonDir := filepath.Join(tmp, "json")
	stdlibPkgDir := filepath.Join(tmp, "stdlibpkg")

	for _, d := range []string{execroot, workspace, outputBase, jsonDir, stdlibPkgDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}

	// First-party source.
	fooSrc := filepath.Join(workspace, "example", "foo", "foo.go")
	mustWrite(t, fooSrc, "package foo\n\nimport \"math/bits\"\n\nvar _ = bits.UintSize\n")

	// Stdlib source (must be parseable; ResolveImports parses CompiledGoFiles).
	bitsSrc := filepath.Join(outputBase, "external", "go_sdk", "src", "math", "bits", "bits.go")
	mustWrite(t, bitsSrc, "package bits\n\nconst UintSize = 64\n")

	rootID := "@@//example/foo:foo"
	stdlibID := "@@renamed_go_rules+custom//stdlib:math/bits"

	rootJSON := `{
  "ID": "` + rootID + `",
  "Name": "foo",
  "PkgPath": "github.com/example/foo",
  "GoFiles": ["__BAZEL_WORKSPACE__/example/foo/foo.go"],
  "CompiledGoFiles": ["__BAZEL_WORKSPACE__/example/foo/foo.go"],
  "ExportFile": "__BAZEL_EXECROOT__/bazel-out/bin/example/foo/foo.x",
  "Imports": {"math/bits": "` + stdlibID + `"}
}`
	stdlibJSON := `{
  "ID": "` + stdlibID + `",
  "Name": "bits",
  "PkgPath": "math/bits",
  "GoFiles": ["__BAZEL_OUTPUT_BASE__/external/go_sdk/src/math/bits/bits.go"],
  "CompiledGoFiles": ["__BAZEL_OUTPUT_BASE__/external/go_sdk/src/math/bits/bits.go"],
  "Standard": true
}`
	mustWrite(t, filepath.Join(jsonDir, "root.pkg.json"), rootJSON)
	mustWrite(t, filepath.Join(jsonDir, "stdlib.pkg.json"), stdlibJSON)

	t.Setenv("GOPACKAGESDRIVER_JSON_DIR", jsonDir)
	t.Setenv("GOPACKAGESDRIVER_ROOTS", rootID)
	t.Setenv("GOPACKAGESDRIVER_STDLIB_PKG_DIR", stdlibPkgDir)
	t.Setenv("GOPACKAGESDRIVER_EXECROOT", execroot)
	t.Setenv("GOPACKAGESDRIVER_WORKSPACE", workspace)
	t.Setenv("GOPACKAGESDRIVER_OUTPUT_BASE", outputBase)

	driverRequest := `{"Mode": 8767, "Tests": true}`

	var out bytes.Buffer
	if err := run(strings.NewReader(driverRequest), &out, nil); err != nil {
		t.Fatalf("run returned error: %v\nstdout: %s", err, out.String())
	}

	var resp packages.DriverResponse
	if err := json.Unmarshal(out.Bytes(), &resp); err != nil {
		t.Fatalf("unable to unmarshal driver response: %v\nstdout: %s", err, out.String())
	}

	// (c) Roots contains the root ID.
	if !contains(resp.Roots, rootID) {
		t.Errorf("resp.Roots = %v; want it to contain %q", resp.Roots, rootID)
	}

	root := findPackageByID(resp.Packages, rootID)
	if root == nil {
		t.Fatalf("root package %q not present in response; packages: %v", rootID, pkgIDs(resp.Packages))
	}

	// (a) __BAZEL_EXECROOT__ placeholder resolved to the execroot.
	wantExport := filepath.Join(execroot, "bazel-out/bin/example/foo/foo.x")
	if root.ExportFile != wantExport {
		t.Errorf("root.ExportFile = %q; want %q", root.ExportFile, wantExport)
	}
	wantSrc := filepath.Join(workspace, "example/foo/foo.go")
	if len(root.CompiledGoFiles) == 0 || root.CompiledGoFiles[0] != wantSrc {
		t.Errorf("root.CompiledGoFiles = %v; want first entry %q", root.CompiledGoFiles, wantSrc)
	}

	// (b) stdlib ExportFile injected from GOPACKAGESDRIVER_STDLIB_PKG_DIR.
	std := findPackageByID(resp.Packages, stdlibID)
	if std == nil {
		t.Fatalf("stdlib package %q not present in response; packages: %v", stdlibID, pkgIDs(resp.Packages))
	}
	wantStdExport := filepath.Join(stdlibPkgDir, runtime.GOOS+"_"+runtime.GOARCH, "math/bits.a")
	if std.ExportFile != wantStdExport {
		t.Errorf("stdlib ExportFile = %q; want %q (injected, ResolvePaths must leave absolute path untouched)", std.ExportFile, wantStdExport)
	}
	// Dependency sources must survive even when ExportFile is available:
	// golangci-lint computes analyzer facts from them on a cold cache.
	if len(resp.Roots) != 1 || resp.Roots[0] != rootID {
		t.Errorf("resp.Roots = %v; want only %q", resp.Roots, rootID)
	}
	if len(std.GoFiles) != 1 || std.GoFiles[0] != bitsSrc {
		t.Errorf("dependency GoFiles = %v; want [%q]", std.GoFiles, bitsSrc)
	}
	if len(std.CompiledGoFiles) != 1 || std.CompiledGoFiles[0] != bitsSrc {
		t.Errorf("dependency CompiledGoFiles = %v; want [%q]", std.CompiledGoFiles, bitsSrc)
	}
}

func mustWrite(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func pkgIDs(pkgs []*packages.Package) []string {
	ids := make([]string, 0, len(pkgs))
	for _, p := range pkgs {
		ids = append(ids, p.ID)
	}
	return ids
}

// Concrete roots must work independently of rules_go's apparent or canonical
// repository name. Standard packages join the graph through imports only.
func TestMatchConcreteRoots(t *testing.T) {
	registry := NewPackageRegistry(bazelVersion{})
	registry.Add(&FlatPackage{ID: "@@custom_main//pkg:lib", Name: "pkg", PkgPath: "example/pkg"})
	registry.Add(&FlatPackage{ID: "@@renamed_go_rules+//stdlib:fmt", Name: "fmt", PkgPath: "fmt", Standard: true})
	roots, pkgs := registry.Match([]string{"@@custom_main//pkg:lib"})
	if len(roots) != 1 || roots[0] != "@@custom_main//pkg:lib" || len(pkgs) != 1 {
		t.Fatalf("Match = %v, %v; want only concrete root", roots, pkgIDs(pkgs))
	}
}
