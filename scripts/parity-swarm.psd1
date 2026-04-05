@{
    RuntimeRoot = 'runtime\parity-swarm'
    StateFile = 'runtime\parity-swarm\swarm-state.json'
    ReadyFileName = 'harness.ready'
    ExperimentalOutput = @{
        Release = 'eMule-v0.60d-experimental-clean\srchybrid\x64\Release\emule.exe'
        Debug   = 'eMule-v0.60d-experimental-clean\srchybrid\x64\Debug\emule.exe'
    }
    Profiles = @(
        @{
            Name = 'node-a'
            BindAddr = '127.0.0.1'
            TcpPort = 42062
            UdpPort = 42072
            ServerUdpPort = 0
            WebPort = 47101
            KadUdpKey = 4206201
            BootstrapPeers = @(
                '127.0.0.1:42082'
                '127.0.0.1:42092'
                '127.0.0.1:42102'
            )
        }
        @{
            Name = 'node-b'
            BindAddr = '127.0.0.1'
            TcpPort = 42082
            UdpPort = 42082
            ServerUdpPort = 0
            WebPort = 47102
            KadUdpKey = 4208201
            BootstrapPeers = @(
                '127.0.0.1:42072'
                '127.0.0.1:42092'
                '127.0.0.1:42102'
            )
        }
        @{
            Name = 'node-c'
            BindAddr = '127.0.0.1'
            TcpPort = 42092
            UdpPort = 42092
            ServerUdpPort = 0
            WebPort = 47103
            KadUdpKey = 4209201
            BootstrapPeers = @(
                '127.0.0.1:42072'
                '127.0.0.1:42082'
                '127.0.0.1:42102'
            )
        }
        @{
            Name = 'node-d'
            BindAddr = '127.0.0.1'
            TcpPort = 42102
            UdpPort = 42102
            ServerUdpPort = 0
            WebPort = 47104
            KadUdpKey = 4210201
            BootstrapPeers = @(
                '127.0.0.1:42072'
                '127.0.0.1:42082'
                '127.0.0.1:42092'
            )
        }
    )
}
