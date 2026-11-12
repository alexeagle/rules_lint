// Vendored from @io_bazel_rules_go //go/tools/gopackagesdriver as of rules_go
// (version recorded in MODULE.bazel). Re-sync when bumping rules_go.
// Only the JSON read + response-assembly half is vendored; the bazel
// query/build half is intentionally omitted.

// Copyright 2021 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"fmt"
	"strings"

	"golang.org/x/tools/go/packages"
)

type PackageRegistry struct {
	packagesByID map[string]*packages.Package
	stdlib       map[string]*packages.Package
	bazelVersion bazelVersion
}

func NewPackageRegistry(bazelVersion bazelVersion, pkgs ...*FlatPackage) *PackageRegistry {
	pr := &PackageRegistry{
		packagesByID: map[string]*packages.Package{},
		stdlib:       map[string]*packages.Package{},
		bazelVersion: bazelVersion,
	}
	pr.Add(pkgs...)
	return pr
}

func (pr *PackageRegistry) Add(pkgs ...*FlatPackage) *PackageRegistry {
	for _, flatPkg := range pkgs {
		imports := make(map[string]*packages.Package)
		for impKey, imp := range flatPkg.Imports {
			imports[impKey] = &packages.Package{
				ID: imp,
			}
		}

		pkg := &packages.Package{
			ID:              flatPkg.ID,
			Name:            flatPkg.Name,
			PkgPath:         flatPkg.PkgPath,
			GoFiles:         flatPkg.GoFiles,
			CompiledGoFiles: flatPkg.CompiledGoFiles,
			OtherFiles:      flatPkg.OtherFiles,
			ExportFile:      flatPkg.ExportFile,
			Imports:         imports,
		}

		if len(pkg.CompiledGoFiles) <= 0 {
			pkg.CompiledGoFiles = pkg.GoFiles
		}

		pr.packagesByID[pkg.ID] = pkg

		if flatPkg.IsStdlib() {
			pr.stdlib[pkg.PkgPath] = pkg
		}
	}
	return pr
}

func (pr *PackageRegistry) ResolvePaths(prf PathResolverFunc) error {
	for _, pkg := range pr.packagesByID {
		ResolvePaths(pkg, prf)
		FilterFilesForBuildTags(pkg)
	}
	return nil
}

// ResolveImports adds stdlib imports to packages. This is required because
// stdlib packages are not part of the JSON file exports as bazel is unaware of
// them.
func (pr *PackageRegistry) ResolveImports(overlays map[string][]byte) error {
	// rules_lint modification: index non-stdlib packages by import path too.
	// Upstream only resolves stdlib here, relying on every package's JSON
	// Imports map being pre-populated. But rules_go's go_deps external repos
	// emit .pkg.json with an empty Imports map, so when such a package is
	// type-checked from source its non-stdlib imports (e.g. another go_dep)
	// would be left unresolved ("could not import ..."). Falling back to a
	// PkgPath index fixes those without affecting packages whose Imports are
	// already populated (ResolveImports skips imports that are already present).
	byPkgPath := make(map[string]*packages.Package, len(pr.packagesByID))
	for _, pkg := range pr.packagesByID {
		if pkg.PkgPath != "" {
			byPkgPath[pkg.PkgPath] = pkg
		}
	}

	resolve := func(importPath string) *packages.Package {
		if pkg, ok := pr.stdlib[importPath]; ok {
			return pkg
		}
		if pkg, ok := byPkgPath[importPath]; ok {
			return pkg
		}

		return nil
	}

	for _, pkg := range pr.packagesByID {
		if err := ResolveImports(pkg, resolve, overlays); err != nil {
			return err
		}

		testPkg := MoveTestFiles(pkg)
		if testPkg != nil {
			pr.packagesByID[testPkg.ID] = testPkg
		}
	}

	return nil
}

func (pr *PackageRegistry) walk(acc map[string]*packages.Package, root string) {
	pkg := pr.packagesByID[root]

	if pkg == nil {
		return
	}

	acc[pkg.ID] = pkg
	for _, pkgI := range pkg.Imports {
		if _, ok := acc[pkgI.ID]; !ok {
			pr.walk(acc, pkgI.ID)
		}
	}
}

func (pr *PackageRegistry) Match(labels []string) ([]string, []*packages.Package) {
	roots := map[string]struct{}{}

	for _, label := range labels {
		// When packagesdriver is ran from rules go, rulesGoRepositoryName will just be @
		if pr.bazelVersion.isAtLeast(bazelVersion{6, 0, 0}) &&
			!strings.HasPrefix(label, "@") {
			// Canonical labels is only since Bazel 6.0.0
			label = fmt.Sprintf("@%s", label)
		}

		// rules_lint modification: roots are concrete package labels supplied
		// by the aspect. The upstream aggregate stdlib-target special case is
		// unused here; stdlib packages are reached through package imports.
		if _, ok := pr.packagesByID[label]; ok {
			roots[label] = struct{}{}
			// If an xtest package exists for this package add it to the roots
			if _, ok := pr.packagesByID[label+"_xtest"]; ok {
				roots[label+"_xtest"] = struct{}{}
			}
		} else {
			// Skip a package if we don't have .pkg.json for it.
			// This happens if 'bazel query' matches the target, but 'bazel build'
			// can't analyze it, for example, if target_compatible_with is set
			// with contraints not compatible with the host platform.
			continue
		}
	}

	walkedPackages := map[string]*packages.Package{}
	retRoots := make([]string, 0, len(roots))
	for rootPkg := range roots {
		retRoots = append(retRoots, rootPkg)
		pr.walk(walkedPackages, rootPkg)
	}

	retPkgs := make([]*packages.Package, 0, len(walkedPackages))
	for _, pkg := range walkedPackages {
		retPkgs = append(retPkgs, pkg)
	}

	return retRoots, retPkgs
}
