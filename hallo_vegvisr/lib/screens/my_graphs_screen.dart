import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/knowledge_graph_service.dart';
import '../services/auth_service.dart';

class MyGraphsScreen extends StatefulWidget {
  const MyGraphsScreen({super.key});

  @override
  State<MyGraphsScreen> createState() => _MyGraphsScreenState();
}

class _MyGraphsScreenState extends State<MyGraphsScreen> {
  final _knowledgeGraphService = KnowledgeGraphService();
  final _authService = AuthService();

  static const String _publicGraphId = 'graph_1767334024408';

  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _graphs = [];

  @override
  void initState() {
    super.initState();
    _loadGraphs();
  }

  Future<void> _loadGraphs() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final phone = await _authService.getPhone();
    final userId = await _authService.getUserId();

    if (phone == null || phone.isEmpty) {
      setState(() {
        _error = 'Not logged in. Please log in again.';
        _loading = false;
      });
      return;
    }

    final result = await _knowledgeGraphService.getMyGraphs(
      phone: phone,
      userId: userId,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _graphs = List<Map<String, dynamic>>.from(result['graphs'] ?? []);
        _loading = false;
      });
    } else {
      setState(() {
        _error = result['error'] ?? 'Failed to load graphs';
        _loading = false;
      });
    }
  }

  Future<void> _deleteGraph(String graphId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Graph'),
        content: Text(
          'Are you sure you want to delete "$title"?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final phone = await _authService.getPhone();
    final userId = await _authService.getUserId();

    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not logged in. Please log in again.')),
      );
      return;
    }

    final result = await _knowledgeGraphService.deleteGraph(
      phone: phone,
      userId: userId,
      graphId: graphId,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Graph deleted successfully')),
      );
      _loadGraphs();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'] ?? 'Failed to delete graph')),
      );
    }
  }

  Future<void> _copyGraphLink(String graphId) async {
    if (graphId.isEmpty) return;
    final graphUrl = KnowledgeGraphService.buildPublicGraphUrl(graphId);
    await Clipboard.setData(ClipboardData(text: graphUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied to clipboard')));
  }

  void _openGraph(String graphId) {
    final graphUrl = KnowledgeGraphService.buildPublicGraphUrl(graphId);
    final url = Uri.parse(graphUrl);
    final messenger = ScaffoldMessenger.of(context);

    launchUrl(url, mode: LaunchMode.externalApplication).catchError((_) {
      Clipboard.setData(ClipboardData(text: graphUrl));
      messenger.showSnackBar(
        const SnackBar(content: Text('URL copied to clipboard')),
      );
      return false;
    });
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Graphs'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/?openDrawer=true'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadGraphs,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/create-graph'),
        tooltip: 'Create Graph',
        backgroundColor: const Color(0xFF4f6d7a),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadGraphs,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final graphs = [
      {
        'id': _publicGraphId,
        'title': 'Public Graph (Community)',
        'createdAt': null,
        'isPublic': true,
      },
      ..._graphs,
    ];

    return RefreshIndicator(
      onRefresh: _loadGraphs,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: graphs.length,
        itemBuilder: (context, index) {
          final graph = graphs[index];
          final title = graph['title'] ?? 'Untitled';
          final graphId = graph['id'] ?? '';
          final isPublic = graph['isPublic'] == true;
          final createdAt = _formatDate(graph['createdAt']);
          final Widget? subtitleWidget = createdAt.isNotEmpty
              ? Text(
                  createdAt,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                )
              : isPublic
              ? const Text(
                  'Public dev graph • editable by everyone',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A6D3B),
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            color: isPublic ? const Color(0xFFFFF3CD) : null,
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isPublic
                      ? const Color(0xFFFFD166)
                      : const Color(0xFF4f6d7a).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isPublic ? Icons.public : Icons.account_tree,
                  color: isPublic
                      ? const Color(0xFF8A6D3B)
                      : const Color(0xFF4f6d7a),
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (subtitleWidget != null) ...[
                    const SizedBox(height: 4),
                    subtitleWidget,
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Color(0xFF4f6d7a),
                        ),
                        onPressed: () => context.push('/edit-graph/$graphId'),
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => _openGraph(graphId),
                        tooltip: 'Open in browser',
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: graphId.isEmpty
                            ? null
                            : () => _copyGraphLink(graphId),
                        tooltip: 'Copy link',
                      ),
                      if (!isPublic)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () => _deleteGraph(graphId, title),
                          tooltip: 'Delete',
                        ),
                    ],
                  ),
                ],
              ),
              onTap: () => context.push('/edit-graph/$graphId'),
            ),
          );
        },
      ),
    );
  }
}
