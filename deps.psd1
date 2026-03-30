@{
    BuildBranch = 'emule-build-v0.72a'
    AppBuildBranch = 'v0.72a-broadband-dev'
    Workspace = @{
        Toolchain = @{
            WindowsTargetPlatformVersion = '10.0'
        }
        LogsRoot = 'logs'
        TempRoot = 'tmp'
        Cleanup = @(
            'logs'
            'dist'
            'tmp'
            'eMule\srchybrid\x64'
        )
        Templates = @{
            zlib = @{
                Source = 'templates\zlib\zlib.vcxproj'
                Destination = 'eMule-zlib\contrib\vstudio\vc\zlib.vcxproj'
            }
        }
        Package = @{
            Release = @{
                SourceProject = 'eMule'
                OutputDir = 'dist'
                ArchiveName = 'eMule0.72a-broadband_x64-snapshot.zip'
                RootDir = 'eMule0.72a-broadband_x64'
                BuildInfoName = 'BUILD-INFO.txt'
                Entry = 'emule.exe'
                Include = @(
                    @{
                        Source = 'LICENSE'
                        Destination = 'LICENSE'
                    }
                )
            }
        }
        GeneratedProjects = @{
            zlib = @{
                ConfigureReady = @(
                    'eMule-zlib\cmake-build\CMakeCache.txt'
                )
                Cleanup = @(
                    'eMule-zlib\cmake-build'
                    'eMule-zlib\contrib\vstudio\vc\x64'
                    'eMule-zlib\contrib\vstudio\vc\zlib.vcxproj'
                )
                Configure = @{
                    Source = 'eMule-zlib'
                    Build = 'eMule-zlib\cmake-build'
                    Generator = 'Visual Studio 17 2022'
                    Platform = 'x64'
                    Arguments = @(
                        '-DZLIB_BUILD_SHARED=OFF'
                        '-DZLIB_BUILD_TESTING=OFF'
                        '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>'
                    )
                }
                BuildArtifacts = @{
                    Release = 'zs.lib'
                    Debug = 'zsd.lib'
                }
            }
        }
    }

    DependencyOrder = @(
        'cryptopp'
        'miniupnp'
        'ResizableLib'
        'zlib'
    )

    BuildProjects = @(
        'cryptopp'
        'miniupnp'
        'ResizableLib'
        'zlib'
    )

    Dependencies = @{
        cryptopp = @{
            Repo = 'eMule-cryptopp'
        }
        miniupnp = @{
            Repo = 'eMule-miniupnp'
        }
        ResizableLib = @{
            Repo = 'eMule-ResizableLib'
        }
        zlib = @{
            Repo = 'eMule-zlib'
        }
    }

    NestedSubmodules = @()

    Projects = @{
        cryptopp = @{
            Kind   = 'msbuild'
            Path   = 'eMule-cryptopp\cryptlib.vcxproj'
            Output = @{
                Release = 'eMule-cryptopp\x64\Release\cryptlib.lib'
                Debug   = 'eMule-cryptopp\x64\Debug\cryptlib.lib'
            }
            Open = 'eMule-cryptopp\cryptlib.vcxproj'
        }
        miniupnp = @{
            Kind   = 'msbuild'
            Path   = 'eMule-miniupnp\miniupnpc\msvc\miniupnpc.vcxproj'
            Output = @{
                Release = 'eMule-miniupnp\miniupnpc\msvc\x64\Release\miniupnpc.lib'
                Debug   = 'eMule-miniupnp\miniupnpc\msvc\x64\Debug\miniupnpc.lib'
            }
            Open = 'eMule-miniupnp\miniupnpc\msvc\miniupnpc.vcxproj'
        }
        ResizableLib = @{
            Kind   = 'msbuild'
            Path   = 'eMule-ResizableLib\ResizableLib\ResizableLib.vcxproj'
            Output = @{
                Release = 'eMule-ResizableLib\ResizableLib\x64\Release\resizablelib.lib'
                Debug   = 'eMule-ResizableLib\ResizableLib\x64\Debug\resizablelib.lib'
            }
            Open = 'eMule-ResizableLib\ResizableLib\ResizableLib.vcxproj'
        }
        zlib = @{
            Kind   = 'cmake'
            Path   = 'eMule-zlib'
            Build  = 'eMule-zlib\cmake-build'
            Output = @{
                Release = 'eMule-zlib\contrib\vstudio\vc\x64\Release\zlib.lib'
                Debug   = 'eMule-zlib\contrib\vstudio\vc\x64\Debug\zlib.lib'
            }
            Open = 'eMule-zlib\contrib\vstudio\vc\zlib.vcxproj'
        }
        eMule = @{
            Kind   = 'msbuild'
            Path   = 'eMule\srchybrid\emule.vcxproj'
            Output = @{
                Release = 'eMule\srchybrid\x64\Release\emule.exe'
                Debug   = 'eMule\srchybrid\x64\Debug\emule.exe'
            }
            Open = 'eMule\srchybrid\emule.sln'
        }
    }
}
