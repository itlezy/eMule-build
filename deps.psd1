@{
    BuildBranch = 'emule-build-v0.72a'

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
