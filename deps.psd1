@{
    BuildBranch = 'emule-build-v0.72a'
    Workspace = @{
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
            mbedtls = @{
                Source = 'templates\mbedtls\mbedTLS.vcxproj'
                Destination = 'eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj'
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
            mbedtls = @{
                ConfigureReady = @(
                    'eMule-mbedtls\visualc\VS2017\CMakeCache.txt'
                    'eMule-mbedtls\visualc\VS2017\library\mbedtls.vcxproj'
                    'eMule-mbedtls\visualc\VS2017\library\mbedx509.vcxproj'
                    'eMule-mbedtls\visualc\VS2017\tf-psa-crypto\core\tfpsacrypto.vcxproj'
                    'eMule-mbedtls\visualc\VS2017\tf-psa-crypto\drivers\builtin\builtin.vcxproj'
                    'eMule-mbedtls\visualc\VS2017\tf-psa-crypto\drivers\everest\everest.vcxproj'
                    'eMule-mbedtls\visualc\VS2017\tf-psa-crypto\drivers\p256-m\p256m.vcxproj'
                )
                Cleanup = @(
                    'eMule-mbedtls\visualc\VS2017'
                )
                Configure = @{
                    Source = 'eMule-mbedtls'
                    Build = 'eMule-mbedtls\visualc\VS2017'
                    Generator = 'Visual Studio 17 2022'
                    Platform = 'x64'
                    Arguments = @(
                        '-DENABLE_PROGRAMS=OFF'
                        '-DENABLE_TESTING=OFF'
                        '-DGEN_FILES=ON'
                        '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>'
                    )
                }
                StaticRuntimeProjects = @(
                    'library\mbedtls.vcxproj'
                    'library\mbedx509.vcxproj'
                    'tf-psa-crypto\core\tfpsacrypto.vcxproj'
                    'tf-psa-crypto\drivers\builtin\builtin.vcxproj'
                    'tf-psa-crypto\drivers\everest\everest.vcxproj'
                    'tf-psa-crypto\drivers\p256-m\p256m.vcxproj'
                )
            }
        }
    }

    DependencyOrder = @(
        'cryptopp'
        'id3lib'
        'miniupnp'
        'ResizableLib'
        'zlib'
        'mbedtls-tf-psa-crypto'
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
            Repo   = 'eMule-cryptopp'
            Patch  = 'cryptopp-CRYPTOPP_8_9_0.patch'
            Commit = 'Apply eMule build patch: cryptopp-CRYPTOPP_8_9_0.patch'
        }
        id3lib = @{
            Repo   = 'eMule-id3lib'
            Patch  = 'id3lib-v3.9.1.patch'
            Commit = 'Apply eMule build patch: id3lib-v3.9.1.patch'
        }
        miniupnp = @{
            Repo   = 'eMule-miniupnp'
            Patch  = 'miniupnpc-miniupnpc_2_3_3.patch'
            Commit = 'Apply eMule build patch: miniupnpc-miniupnpc_2_3_3.patch'
        }
        ResizableLib = @{
            Repo   = 'eMule-ResizableLib'
            Patch  = 'resizablelib-master.patch'
            Commit = 'Apply eMule build patch: resizablelib-master.patch'
        }
        zlib = @{
            Repo   = 'eMule-zlib'
            Patch  = 'zlib-v1.3.2.patch'
            Commit = 'Apply eMule build patch: zlib-v1.3.2.patch'
        }
        'mbedtls-tf-psa-crypto' = @{
            Repo   = 'eMule-mbedtls\tf-psa-crypto'
            Patch  = 'mbedtls-tf-psa-crypto-v1.0.0.patch'
            Commit = 'Apply eMule build patch: mbedtls-tf-psa-crypto-v1.0.0.patch'
        }
        mbedtls = @{
            Repo   = 'eMule-mbedtls'
            Patch  = 'mbedtls-mbedtls-4.0.0.patch'
            Commit = 'Apply eMule build patch: mbedtls-mbedtls-4.0.0.patch'
        }
    }

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
            Path   = 'eMule-zlib'
            Build  = 'eMule-zlib\cmake-build'
            Output = @{
                Release = 'eMule-zlib\contrib\vstudio\vc\x64\Release\zlib.lib'
                Debug   = 'eMule-zlib\contrib\vstudio\vc\x64\Debug\zlib.lib'
            }
            Open = 'eMule-zlib\contrib\vstudio\vc\zlib.vcxproj'
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
            Path   = 'eMule\srchybrid\emule.vcxproj'
            Output = @{
                Release = 'eMule\srchybrid\x64\Release\emule.exe'
                Debug   = 'eMule\srchybrid\x64\Debug\emule.exe'
            }
            Open = 'eMule\srchybrid\emule.sln'
        }
    }
}
