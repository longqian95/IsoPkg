# IsoPkg

Environment-isolated package manager

**No more package version conflicts. Keep every package the newest version.**

Manage packages by creating its own isolated project environment for every direct installed package. The direct installed packages will never conflict with each others. If updating a package, it can always be upgraded to the newest version. Even same package with different versions can be installed all together.

## Showcase:

If `]add UnicodePlots@1.2.0 StatsBase@0.33.0` in Julia v1.4, then it will return `ERROR: Unsatisfiable requirements detected for package StatsBase [2913bbd2]` because of the version restrictions of package dependencies (see [1], [2]).

With `IsoPkg`, simplely `using IsoPkg; IsoPkg.add("UnicodePlots@1.2.0"); IsoPkg.add("StatsBase@0.33.0")`, then both packages can be used together: `@iso using UnicodePlots "1.2.0"; @iso using StatsBase "0.33.0"`

## Implementation detail:

This package simply creates `env_isolated_packages` folder in `~/.julia`. Then creates a folder (default is Julia version) for grouping each group of packages. Installing package will create an isolated environment in the activated group folder. Before operating or loading a package, the corresponding environment will be activated automatically. The whole process is quite lightweight. You can just manage the folders in `~/.julia/env_isolated_packages` manually to manage the installed packages.

<!-- reference -->
[1]: https://www.juliabloggers.com/understanding-package-version-restrictions-in-julia/
[2]: https://www.juliabloggers.com/my-practices-for-managing-project-dependencies-in-julia/

# Installation

`]add https://github.com/longqian95/IsoPkg.git`

# Usage

- install a package: `IsoPkg.add(pkg_name)`
- install a package and pin to specific version: `IsoPkg.add(pkg_name@ver)`
- remove a package: `IsoPkg.rm(pkg_name)`
- update a package: `IsoPkg.update(pkg_name)`
- update all installed packages: `IsoPkg.update()`
- package status: `IsoPkg.status(pkg_name)`
- status of all installed packages: `IsoPkg.status()`
- operate in a package environment: `@iso pkg_name statement`
- using/import package: `@iso using/import pkg_name`
- using/import package with specific version: `@iso using/import pkg_name ver`
- switch package group: `IsoPkg.swith(group_name)`

# Examples

```julia
using IsoPkg

IsoPkg.switch("test") #switch current project group to "test"

IsoPkg.add("Glob") #install Glob
IsoPkg.add("Glob@1.2.0") #install Glob v1.2.0 and pin the version

@iso using Glob #load Glob
@iso using Glob "1.2.0" #load Glob v1.2.0

using Pkg; @iso "Glob1" pkg"add Glob@1.3.0" #add Glob v1.3.0 as name Glob1
@iso "Glob1" using Glob #load Glob v1.3.0

IsoPkg.status() #show status
IsoPkg.update() #update all packages

IsoPkg.rm("Glob1") #remove Glob v1.3.0
```
