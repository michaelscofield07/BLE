import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/intelligent_sos_service.dart';
import '../services/sos_service.dart';

class IntelligentSosScreen extends StatefulWidget {
  const IntelligentSosScreen({super.key});

  @override
  State<IntelligentSosScreen> createState() => _IntelligentSosScreenState();
}

class _IntelligentSosScreenState extends State<IntelligentSosScreen> {
  Map<String, dynamic> _deviceContext = {};
  Map<String, dynamic> _networkIntelligence = {};
  List<Map<String, dynamic>> _ackData = [];

  @override
  void initState() {
    super.initState();
    _initializeData();
    _setupStreams();
  }

  void _initializeData() async {
    _deviceContext = IntelligentSosService.deviceContext;
    _networkIntelligence = IntelligentSosService.networkIntelligence;
    _ackData = IntelligentSosService.ackData;
  }

  void _setupStreams() {
    IntelligentSosService.deviceContextStream.listen((context) {
      if (mounted) {
        setState(() {
          _deviceContext = context;
        });
      }
    });

    IntelligentSosService.networkIntelligenceStream.listen((network) {
      if (mounted) {
        setState(() {
          _networkIntelligence = network;
        });
      }
    });

    IntelligentSosService.ackDataStream.listen((acks) {
      if (mounted) {
        setState(() {
          _ackData = acks;
        });
      }
    });
  }

  Future<void> _refreshData() async {
    await IntelligentSosService.initialize();
    _initializeData();
  }

  Color _getBatteryColor(int level) {
    if (level >= 60) return Colors.green;
    if (level >= 30) return Colors.orange;
    return Colors.red;
  }

  Color _getStabilityColor(double score) {
    if (score >= 0.7) return Colors.green;
    if (score >= 0.4) return Colors.orange;
    return Colors.red;
  }

  Color _getCrowdColor(String level) {
    switch (level) {
      case 'CROWDED':
        return Colors.green;
      case 'MODERATE':
        return Colors.orange;
      case 'SPARSE':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red[700],
        title: const Text(
          'Intelligent SOS',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device Context Card
              _buildDeviceContextCard(),
              const SizedBox(height: 16),
              
              // Network Intelligence Card
              _buildNetworkIntelligenceCard(),
              const SizedBox(height: 16),
              
              // ACK Data Card
              _buildAckDataCard(),
              const SizedBox(height: 16),
              
              // Decision Making Card
              _buildDecisionCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceContextCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.phone_android, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Device Context',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Battery Status
            Row(
              children: [
                const Icon(Icons.battery_full),
                const SizedBox(width: 8),
                Text('Battery: ${_deviceContext['batteryLevel'] ?? 'Unknown'}%'),
                const Spacer(),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getBatteryColor(_deviceContext['batteryLevel'] ?? 0),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_deviceContext['isCharging'] == true ? 'Charging' : 'Not Charging'),
              ],
            ),
            const SizedBox(height: 12),
            
            // Temperature
            Row(
              children: [
                const Icon(Icons.thermostat),
                const SizedBox(width: 8),
                Text('Temperature: ${(_deviceContext['temperature'] ?? -1).toStringAsFixed(1)}°C'),
                if ((_deviceContext['temperature'] ?? 0) > 42.0) ...[
                  const Spacer(),
                  const Icon(Icons.warning, color: Colors.orange),
                  const Text('Overheating', style: TextStyle(color: Colors.orange)),
                ],
              ],
            ),
            
            const SizedBox(height: 8),
            Text(
              'Last Updated: ${_deviceContext['lastUpdated'] != null ? 
                DateTime.fromMillisecondsSinceEpoch(_deviceContext['lastUpdated']).toString().substring(0, 19) : 
                'Unknown'}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkIntelligenceCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.network_check, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Network Intelligence',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Stability Score
            Row(
              children: [
                const Icon(Icons.signal_cellular_alt),
                const SizedBox(width: 8),
                Text('Stability: ${((_networkIntelligence['stabilityScore'] ?? 0) * 100).toStringAsFixed(0)}%'),
                const Spacer(),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getStabilityColor(_networkIntelligence['stabilityScore'] ?? 0),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Crowd Level
            Row(
              children: [
                const Icon(Icons.groups),
                const SizedBox(width: 8),
                Text('Crowd: ${_networkIntelligence['crowdLevel'] ?? 'UNKNOWN'}'),
                const Spacer(),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getCrowdColor(_networkIntelligence['crowdLevel'] ?? 'UNKNOWN'),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Stable Nodes
            Row(
              children: [
                const Icon(Icons.hub),
                const SizedBox(width: 8),
                Text('Stable Nodes: ${_networkIntelligence['stableNodeCount'] ?? 0}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAckDataCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.purple),
                const SizedBox(width: 8),
                const Text(
                  'Acknowledgments',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text('${_ackData.length} total'),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_ackData.isEmpty)
              const Text('No acknowledgments received yet')
            else
              SizedBox(
                height: 150,
                child: ListView.builder(
                  itemCount: _ackData.length.clamp(0, 10),
                  itemBuilder: (context, index) {
                    final ack = _ackData[_ackData.length - 1 - index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text(ack['ackId'] ?? 'Unknown'),
                      subtitle: Text('RSSI: ${ack['rssi'] ?? 'N/A'} dBm'),
                      trailing: Text(
                        ack['timestamp'] != null 
                          ? DateTime.fromMillisecondsSinceEpoch(ack['timestamp']).toString().substring(11, 19)
                          : 'Unknown',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDecisionCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.psychology, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'AI Decision Making',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            FutureBuilder<Map<String, dynamic>>(
              future: IntelligentSosService.getSosDecision(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (!snapshot.hasData) {
                  return const Text('Unable to get decision');
                }
                
                final decision = snapshot.data!;
                
                return Column(
                  children: [
                    Row(
                      children: [
                        const Text('Should Forward:'),
                        const Spacer(),
                        Switch(
                          value: decision['shouldForward'] == true,
                          onChanged: null, // Read-only
                          activeThumbColor: Colors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    Row(
                      children: [
                        const Text('Priority:'),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getPriorityColor(decision['priority']),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            decision['priority']?.toString().toUpperCase() ?? 'NORMAL',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    if (decision['selectedNodes'] != null && 
                        (decision['selectedNodes'] as List).isNotEmpty) ...[
                      const Text('Selected Nodes:'),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: (decision['selectedNodes'] as List)
                            .map<Widget>((node) => Chip(
                                  label: Text(node.toString()),
                                  backgroundColor: Colors.blue[100],
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Reason: ${decision['reason'] ?? 'No reason provided'}',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(String? priority) {
    switch (priority) {
      case 'high':
        return Colors.red;
      case 'normal':
        return Colors.blue;
      case 'low':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}
