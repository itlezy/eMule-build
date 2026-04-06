@{
    BuildBranch = 'emule-build-v0.72a'
    AppBuildBranch = 'bb/v0.72a/build'
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
            'eMule-bb-v0.72a-build\srchybrid\x64'
        )
        AppRepo = @{
            SeedRepo = @{
                Path = 'eMule-bb-v0.72a-build'
                Url = 'https://github.com/itlezy/eMule.git'
                Branch = 'bb/v0.72a/build'
            }
            CompareSubdir = 'srchybrid'
            Variants = @(
                @{ Name = 'build'; Branch = 'bb/v0.72a/build'; Path = 'eMule-bb-v0.72a-build' }
                @{ Name = 'test'; Branch = 'bb/v0.72a/test'; Path = 'eMule-bb-v0.72a-test' }
                @{ Name = 'bugfix'; Branch = 'bb/v0.72a/bugfix'; Path = 'eMule-bb-v0.72a-bugfix' }
            )
        }
        Templates = @{
            zlib = @{
                Source = 'templates\zlib\zlib.vcxproj'
                Destination = 'eMule-zlib\zlib\contrib\vstudio\vc\zlib.vcxproj'
            }
            mbedtls = @{
                Source = 'templates\mbedtls\mbedTLS.vcxproj'
                Destination = 'eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj'
            }
        }
        Package = @{
            Release = @{
                SourceProject = 'eMule'
                OutputDir = 'dist'
                ArchiveName = 'eMule0.72a-build_x64-snapshot.zip'
                RootDir = 'eMule0.72a-build_x64'
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
                    'eMule-zlib\cmake-build-x64\CMakeCache.txt'
                )
                Cleanup = @(
                    'eMule-zlib\cmake-build-x64'
                    'eMule-zlib\cmake-build-ARM64'
                    'eMule-zlib\zlib\contrib\vstudio\vc\x64'
                    'eMule-zlib\zlib\contrib\vstudio\vc\ARM64'
                    'eMule-zlib\zlib\contrib\vstudio\vc\zlib.vcxproj'
                )
                Configure = @{
                    Source = 'eMule-zlib\zlib'
                    Build = 'eMule-zlib\cmake-build-x64'
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
            mbedtls = @{
                ConfigureReady = @(
                    'eMule-mbedtls\visualc\VS2017-x64\CMakeCache.txt'
                    'eMule-mbedtls\visualc\VS2017-x64\library\mbedtls.vcxproj'
                    'eMule-mbedtls\visualc\VS2017-x64\library\mbedx509.vcxproj'
                )
                Cleanup = @(
                    'eMule-mbedtls\visualc\VS2017-x64'
                    'eMule-mbedtls\visualc\VS2017-ARM64'
                    'eMule-mbedtls\visualc\VS2017\x64'
                    'eMule-mbedtls\visualc\VS2017\ARM64'
                    'eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj'
                )
                Configure = @{
                    Source = 'eMule-mbedtls'
                    Build = 'eMule-mbedtls\visualc\VS2017-x64'
                    Generator = 'Visual Studio 17 2022'
                    Platform = 'x64'
                    Arguments = @(
                        '-DENABLE_PROGRAMS=OFF'
                        '-DENABLE_TESTING=OFF'
                        '-DGEN_FILES=ON'
                        '-DCMAKE_POLICY_VERSION_MINIMUM=3.5'
                        '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW'
                        '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>'
                    )
                }
            }
        }
    }

    DependencyOrder = @(
        'cryptopp'
        'id3lib'
        'miniupnp'
        'ResizableLib'
        'zlib'
        'mbedtls'
    )

    BuildProjects = @(
        'cryptopp'
        'id3lib'
        'miniupnp'
        'ResizableLib'
        'zlib'
        'mbedtls'
    )

    Dependencies = @{
        cryptopp = @{
            Repo = 'eMule-cryptopp'
            Version = '8.9.0'
            Upstream = @{
                Url = 'https://github.com/weidai11/cryptopp'
                Ref = 'CRYPTOPP_8_9_0'
            }
            Policy = @{
                Mode = 'track-latest-upstream'
                Notes = @(
                    'Prefer upstream Crypto++ releases.'
                    'Keep workspace deltas limited to build integration only.'
                )
            }
        }
        id3lib = @{
            Repo = 'eMule-id3lib'
            Version = '3.9.1'
            Upstream = @{
                Url = 'https://github.com/itlezy/eMule-id3lib'
                Ref = 'v3.9.1'
            }
            Policy = @{
                Mode = 'frozen'
                Notes = @(
                    'Legacy dependency kept stable for compatibility.'
                    'Only change for break/fix or unavoidable toolchain maintenance.'
                )
            }
        }
        miniupnp = @{
            Repo = 'eMule-miniupnp'
            Version = '2.3.3'
            Upstream = @{
                Url = 'https://github.com/miniupnp/miniupnp'
                Ref = 'miniupnpc_2_3_3'
            }
            Policy = @{
                Mode = 'track-latest-upstream'
                Notes = @(
                    'Track the latest MiniUPnPc client-library release.'
                    'Do not confuse miniupnpc with miniupnpd daemon-only releases.'
                )
            }
        }
        ResizableLib = @{
            Repo = 'eMule-ResizableLib'
            Version = 'master'
            Upstream = @{
                Url = 'https://github.com/ppescher/resizablelib'
                Ref = 'master'
            }
            Policy = @{
                Mode = 'frozen'
                Notes = @(
                    'Freeze on the current fork state.'
                    'The eMuleAI stale-anchor memory leak fix is already present in this fork.'
                )
            }
        }
        zlib = @{
            Repo = 'eMule-zlib'
            Version = '1.3.2'
            Upstream = @{
                Url = 'https://github.com/madler/zlib'
                Ref = 'v1.3.2'
            }
            Policy = @{
                Mode = 'track-latest-upstream'
                Notes = @(
                    'Prefer upstream zlib releases.'
                    'Use CMake as the source of truth for generated project files.'
                )
            }
        }
        mbedtls = @{
            Repo = 'eMule-mbedtls'
            Version = '4.1.0'
            Upstream = @{
                Url = 'https://github.com/Mbed-TLS/mbedtls'
                Ref = 'mbedtls-4.1.0'
            }
            Policy = @{
                Mode = 'track-latest-upstream'
                Notes = @(
                    'Prefer upstream Mbed TLS releases.'
                    'Use CMake generation and keep wrapper changes minimal.'
                )
            }
        }
    }

    NestedSubmodules = @()

    Projects = @{
        cryptopp = @{
            Kind   = 'msbuild'
            Path   = 'eMule-cryptopp\cryptopp\cryptlib.vcxproj'
            Output = @{
                Release = 'eMule-cryptopp\cryptopp\x64\Release\cryptlib.lib'
                Debug   = 'eMule-cryptopp\cryptopp\x64\Debug\cryptlib.lib'
            }
            Open = 'eMule-cryptopp\cryptopp\cryptlib.vcxproj'
        }
        id3lib = @{
            Kind   = 'msbuild'
            Path   = 'eMule-id3lib\libprj\id3lib.vcxproj'
            Output = @{
                Release = 'eMule-id3lib\libprj\x64\Release\id3lib.lib'
                Debug   = 'eMule-id3lib\libprj\x64\Debug\id3lib.lib'
            }
            Open = 'eMule-id3lib\libprj\id3lib.vcxproj'
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
            Path   = 'eMule-zlib\zlib'
            Build  = 'eMule-zlib\cmake-build-x64'
            Output = @{
                Release = 'eMule-zlib\zlib\contrib\vstudio\vc\x64\Release\zlib.lib'
                Debug   = 'eMule-zlib\zlib\contrib\vstudio\vc\x64\Debug\zlib.lib'
            }
            Open = 'eMule-zlib\zlib\contrib\vstudio\vc\zlib.vcxproj'
        }
        mbedtls = @{
            Kind   = 'msbuild'
            Path   = 'eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj'
            Output = @{
                Release = 'eMule-mbedtls\visualc\VS2017\x64\Release\mbedtls.lib'
                Debug   = 'eMule-mbedtls\visualc\VS2017\x64\Debug\mbedtls.lib'
            }
            Open = 'eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj'
        }
        eMule = @{
            Kind   = 'msbuild'
            Path   = 'eMule-bb-v0.72a-build\srchybrid\emule.vcxproj'
            Output = @{
                Release = 'eMule-bb-v0.72a-build\srchybrid\x64\Release\emule.exe'
                Debug   = 'eMule-bb-v0.72a-build\srchybrid\x64\Debug\emule.exe'
            }
            Open = 'eMule-bb-v0.72a-build\srchybrid\emule.vcxproj'
        }
    }
}
