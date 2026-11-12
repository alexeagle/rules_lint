// A static, file-reading GOPACKAGESDRIVER for hermetic golangci-lint runs.
//
// Unlike the upstream rules_go gopackagesdriver, this binary never invokes
// bazel at runtime. It reads pre-staged FlatPackage JSON (*.pkg.json) from a
// directory named by GOPACKAGESDRIVER_JSON_DIR, resolves the bazel placeholder
// paths from environment variables, and assembles a packages.DriverResponse.
//
// Two behaviors differ from a naive port of the rules_go driver:
//
//  1. Stdlib ExportFile injection. golangci-lint typechecks dependencies from
//     each package's ExportFile, but rules_go's stdlib .pkg.json carry an empty
//     ExportFile. rules_go separately provides precompiled stdlib archives at
//     <STDLIB_PKG_DIR>/<GOOS>_<GOARCH>/<importpath>.a, so for every Standard
//     package we synthesize that absolute path before it enters the registry.
//
//  2. Roots come from the environment, not query args. The static driver cannot
//     resolve golangci-lint's ./... / file= patterns (that requires bazel
//     query), so os.Args is ignored and roots are read from
//     GOPACKAGESDRIVER_ROOTS (space-separated bazel labels).

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"golang.org/x/tools/go/packages"
)

// workspaceRoot is referenced by the vendored utils.go helpers. The static
// driver resolves paths via pathResolver() rather than these helpers, but the
// symbol must exist for the package to compile.
var workspaceRoot = os.Getenv("GOPACKAGESDRIVER_WORKSPACE")

// bazelVersion mirrors the type the vendored packageregistry.go expects. The
// zero value makes isAtLeast report "at least" any version, matching upstream's
// treatment of unparseable (development) Bazel versions and yielding the
// canonical-label (@-prefixed) matching path used by Bazel >= 6.
type bazelVersion [3]int

func (a bazelVersion) compare(b bazelVersion) int {
	for i := 0; i < len(a); i++ {
		if c := a[i] - b[i]; c != 0 {
			return c
		}
	}
	return 0
}

func (a bazelVersion) isAtLeast(b bazelVersion) bool {
	return a.compare(b) >= 0 || a == bazelVersion{}
}

// pathResolver returns a PathResolverFunc that replaces the three bazel
// placeholders with absolute paths drawn from the environment. Each placeholder
// is replaced once, matching upstream's single-replacement semantics. Already
// absolute paths (e.g. an injected stdlib ExportFile) contain no placeholder
// and are returned unchanged.
func pathResolver() PathResolverFunc {
	execroot := getenvDefault("GOPACKAGESDRIVER_EXECROOT", mustCwd())
	workspace := getenvDefault("GOPACKAGESDRIVER_WORKSPACE", mustCwd())
	outputBase := getenvDefault("GOPACKAGESDRIVER_OUTPUT_BASE", mustCwd())

	return func(p string) string {
		p = strings.Replace(p, "__BAZEL_EXECROOT__", execroot, 1)
		p = strings.Replace(p, "__BAZEL_WORKSPACE__", workspace, 1)
		p = strings.Replace(p, "__BAZEL_OUTPUT_BASE__", outputBase, 1)
		return p
	}
}

func mustCwd() string {
	if cwd, err := os.Getwd(); err == nil {
		return cwd
	}
	return "."
}

// stagedJSONFiles globs the *.pkg.json files staged under
// GOPACKAGESDRIVER_JSON_DIR.
func stagedJSONFiles() ([]string, error) {
	dir := os.Getenv("GOPACKAGESDRIVER_JSON_DIR")
	if dir == "" {
		return nil, fmt.Errorf("GOPACKAGESDRIVER_JSON_DIR is not set")
	}
	files, err := filepath.Glob(filepath.Join(dir, "*.pkg.json"))
	if err != nil {
		return nil, fmt.Errorf("unable to glob staged JSON files: %w", err)
	}
	return files, nil
}

// stdlibExportFile returns the absolute path to the precompiled stdlib archive
// for the given import path, or "" if GOPACKAGESDRIVER_STDLIB_PKG_DIR is unset.
func stdlibExportFile(pkgPath string) string {
	dir := os.Getenv("GOPACKAGESDRIVER_STDLIB_PKG_DIR")
	if dir == "" {
		return ""
	}
	return filepath.Join(dir, runtime.GOOS+"_"+runtime.GOARCH, pkgPath+".a")
}

// run reads a DriverRequest from in, assembles the package graph from the
// staged JSON, and writes a packages.DriverResponse to out. args is ignored on
// purpose (see package doc, behavior 2).
func run(in io.Reader, out io.Writer, _ []string) error {
	request, err := ReadDriverRequest(in)
	if err != nil {
		return fmt.Errorf("unable to read request: %w", err)
	}

	jsonFiles, err := stagedJSONFiles()
	if err != nil {
		return err
	}

	// Inline the assembly that NewJSONPackagesDriver performs, so the stdlib
	// ExportFile can be injected in the walk callback BEFORE registry.Add and
	// therefore before ResolvePaths/ResolveImports. The injected value is a
	// fully-resolved absolute path, so the subsequent ResolvePaths leaves it
	// untouched (no placeholder to replace).
	roots := strings.Fields(os.Getenv("GOPACKAGESDRIVER_ROOTS"))
	registry := NewPackageRegistry(bazelVersion{})
	for _, f := range jsonFiles {
		if err := WalkFlatPackagesFromJSON(f, func(pkg *FlatPackage) {
			if pkg.IsStdlib() && pkg.ExportFile == "" {
				if exp := stdlibExportFile(pkg.PkgPath); exp != "" {
					pkg.ExportFile = exp
				}
			}
			// Keep dependency source lists: golangci-lint needs source to compute
			// cross-package analyzer facts on a cold cache. Compiler exports
			// provide types, not analyzer facts. Roots below select lint targets.
			registry.Add(pkg)
		}); err != nil {
			return fmt.Errorf("unable to walk json %s: %w", f, err)
		}
	}

	if err := registry.ResolvePaths(pathResolver()); err != nil {
		return fmt.Errorf("unable to resolve paths: %w", err)
	}

	if err := registry.ResolveImports(request.Overlay); err != nil {
		return fmt.Errorf("unable to resolve imports: %w", err)
	}

	rootPkgs, paks := registry.Match(roots)

	resp := &packages.DriverResponse{
		NotHandled: false,
		Compiler:   "gc",
		Arch:       runtime.GOARCH,
		Roots:      rootPkgs,
		Packages:   paks,
	}

	data, err := json.Marshal(resp)
	if err != nil {
		return fmt.Errorf("unable to marshal response: %w", err)
	}
	_, err = out.Write(data)
	return err
}

func main() {
	if err := run(os.Stdin, os.Stdout, os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		// go/packages treats a non-zero exit code as "driver failed" and falls
		// back to `go list`, which would defeat hermeticity and mask the real
		// error. Force a 0 exit so the hermetic action surfaces our message.
		os.Exit(0)
	}
}
