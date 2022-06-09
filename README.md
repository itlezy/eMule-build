# Build package for eMule Community

Meant to ease the build work, all projects upgraded to VS 2019, compiling, with correct path references and updated libraries (as much as possible)

## Pre-requisites
1. Have a recent `git` installed and available on `PATH`
2. Ensure the command `mklink` is available on your Windows system, otherwise get `junction` from Sysinternals and modify `002_create_symlinks.cmd` accordingly
3. Have Visual Studio 2019 Community installed with Windows SDK 10.0 and Toolset v142 (should all be by default when you install C++ components for Visual Studio)

## Build Steps
This git repo contains accessory scripts to clone the other repos and perform the builds. So clone this repo as first step.

### 001_clone_git_repos
First step is to run `001_clone_git_repos.cmd` and then you will have the following directories, which are all the cleaned-up and as much as possible up to date dependencies to build eMule, plus the program directory itself.

```
eMule-cryptopp-8.4.0
eMule-CxImage-7.02
eMule-id3lib-3.9.1
eMule-libpng-1.5.30
eMule-mbedtls-2.28
eMule-miniupnp-2.2.3
eMule-ResizableLib
eMule-zlib-1.2.12
eMule
```

### 002_create_symlinks
Second step is to run `002_create_symlinks.cmd` just to keep some source code references to include directories unchanged in eMule main project.

Then there are scripts each to `launch_VS` if you want to play around with the libraries or the main project, and scripts `build_MSBuild` to launch the builds of each.

The directory `libs` is the place where built libraries are copied and referenced by the linker of the main eMule project to build the final executable file.

The external libraries should require no change at this stage, so they are mostly for reference and all forked from their original repositories for integrity. Minor changes had to be made to build them on Visual Studio 2019, which you can see in git history.

### 003_build_MSBuild_ALL_libs
Finally you should be ready to go, this last script `003_build_MSBuild_ALL_libs.cmd` launches all the library builds in parallel. As last step you will have to build eMule `build_MSBuild_eMule.cmd` as of course it depends on all the libraries that you just built.

### Notes
Please note that I have upgraded few libraries such as libpng, cryptopp, etc.. just taking the most recent minor version from their current git repositories, where applicable. Some others such as ResizableLib or CxImage are not really recent nor maintained. Due to the library upgrades and some other compiler switch changes, please ensure you test properly this build, as I am now doing.
