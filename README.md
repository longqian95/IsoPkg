# IsoPkg

Environment-isolated package manager

Manage packages by ensuring every direct installed package has its own isolated environment. Therefore, the direct installed packages will never conflict with each others. If updating a package, it can always upgrade to the newest version. Even same package with different versions can be installed all together.

This package simply create "env_isolated_packages" folder in "~/.julia". Then create a group folder (default is Julia version) for every group of packages. Installing package will create an isolated environment in the activated group folder. Before operating or loading a package, the corresponding environment will be activated automatically. The whole process is quite lightweight. You can just manage "~/.julia/env_isolated_packages" manually.

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

    IsoPkg.add("Glob") #install Glob
    IsoPkg.add("Glob@1.2.0") #install Glob v1.2.0
    @iso using Glob #load Glob
    @iso using Glob "1.2.0" #load Glob v1.2.0
    using Pkg; @iso "Glob1" pkg"add Glob@1.3.0" #add Glob v1.3.0 with name Glob1
    @iso "Glob1" using Glob #load Glob v1.3.0
    IsoPkg.status() #show status
    IsoPkg.update() #update
    IsoPkg.rm("Glob1") #remove Glob v1.3.0
