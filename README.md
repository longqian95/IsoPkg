# IsoPkg

Environment-isolated package manager

**No more package version conflicts. Easily upgrade packages to the newest version. Scripts keep working after package upgrading**

Manage packages by creating their own isolated project environment for every directly installed package. The directly installed packages will never conflict with each other. If updating a package, it can always be upgraded to the newest version. Even the same package with different versions can be installed together. Scripts can easily specify dependent packages and never need to worry about the package upgrading.

## Showcase:

If `]add UnicodePlots@1.2.0 StatsBase@0.33.0` in Julia v1.4, then it will return `ERROR: Unsatisfiable requirements detected for package StatsBase [2913bbd2]` because of the version restrictions of package dependencies (see [1], [2]).

With `IsoPkg`, simplely `using IsoPkg; IsoPkg.add("UnicodePlots@1.2.0"); IsoPkg.add("StatsBase@0.33.0")`, then both packages can be used together: `@iso using UnicodePlots "1.2.0"; @iso using StatsBase "0.33.0"` (Notice: this will bypass the version compatibility check). Foremore, the script loading UnicodePlots or StatsBase as this form will always work without worrying about the package upgrading.

## Implementation detail:

This package simply creates the `env_isolated_packages` folder in `~/.julia`. Then creates a folder (default is Julia version) for grouping the packages. Installing package will create an isolated environment in the activated group folder. Before operating or loading a package, the corresponding environment will be activated automatically. The whole process is quite lightweight. You can even manually manage the folders in `~/.julia/env_isolated_packages` to manage the installed packages.

<!-- reference -->
[1]: https://www.juliabloggers.com/understanding-package-version-restrictions-in-julia/
[2]: https://www.juliabloggers.com/my-practices-for-managing-project-dependencies-in-julia/

# Installation

`]add https://github.com/longqian95/IsoPkg.git`

# Usage

- install a package: `IsoPkg.add(pkg_name)`
- install a package and pin to the specified version: `IsoPkg.add(pkg_name@version)`
- remove a package: `IsoPkg.rm(pkg_name)`
- update a package: `IsoPkg.update(pkg_name)`
- update all installed packages: `IsoPkg.update()`
- show package status: `IsoPkg.status(pkg_name)`
- show status of all installed packages: `IsoPkg.status()`
- operate in a package environment: `@iso pkg_name statement`
- using/import package: `@iso using/import pkg_name`
- using/import package with the specified version: `@iso using/import pkg_name version`
- switch package group: `IsoPkg.swith(group_name)`
- pin the package version: `IsoPkg.pin(pkg_name)`
- free the package version: `IsoPkg.pin(pkg_name)`

# Examples

```julia
using IsoPkg

IsoPkg.switch("test") #Switch the current project group to "test". Assume it is empty.

IsoPkg.add("Glob") #Install Glob
IsoPkg.add("Glob@1.2.0") #Install Glob v1.2.0 and pin the version

#Notice: If the following `using` statements are in the same session, only the first one does the real loading.
@iso using Glob #Load Glob
@iso using Glob "1.2.0" #Load Glob v1.2.0

using Pkg; @iso "Glob1" pkg"add Glob@1.3.0" #Add Glob v1.3.0 as name Glob1
@iso "Glob1" using Glob #Load Glob v1.3.0

IsoPkg.pin("Glob") #Pin Glob version (will automatically change its name to match the version)
IsoPkg.free("Glob@1.2.0") #Free Glob v1.2.0 version (will automatically remove the version in its name)

IsoPkg.status() #Show status of all packages
IsoPkg.update() #Update all packages

IsoPkg.rm("Glob1") #Remove Glob v1.3.0
IsoPkg.rm("Glob") #Remove Glob
IsoPkg.rm("Glob") #Because there is only one version left, the version number can be omitted
```
