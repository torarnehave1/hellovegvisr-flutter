import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown/markdown.dart' as md;

import '../services/auth_service.dart';
import '../services/knowledge_graph_service.dart';

class GraphViewerScreen extends StatefulWidget {
  final String graphId;
  final String? title;

  const GraphViewerScreen({super.key, required this.graphId, this.title});

  @override
  State<GraphViewerScreen> createState() => _GraphViewerScreenState();
}

class _GraphViewerScreenState extends State<GraphViewerScreen> {
  final _authService = AuthService();
  final _knowledgeGraphService = KnowledgeGraphService();

  bool _loading = true;
  String _error = '';
  String _markdown = '';
  String _title = '';

  @override
  void initState() {
    super.initState();
    _loadGraph();
  }

  Future<void> _loadGraph() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final phone = await _authService.getPhone();
    final userId = await _authService.getUserId();

    if (phone == null || phone.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Not logged in. Please log in again.';
      });
      return;
    }

    final result = await _knowledgeGraphService.getGraph(
      phone: phone,
      userId: userId,
      graphId: widget.graphId,
    );

    if (!mounted) return;

    if (result['success'] == true && result['graph'] is Map) {
      final graph = Map<String, dynamic>.from(result['graph'] as Map);

      String content = (graph['content'] ?? '').toString();
      if (content.trim().isEmpty && graph['nodes'] is List) {
        final nodes = graph['nodes'] as List;
        if (nodes.isNotEmpty) {
          final first = nodes.first;
          if (first is Map) {
            final firstMap = Map<String, dynamic>.from(first);
            content = (firstMap['info'] ?? firstMap['content'] ?? '')
                .toString();
          }
        }
      }
      final footerIndex = content.lastIndexOf('\n\n---\n\n*Created by:');
      if (footerIndex > 0) {
        content = content.substring(0, footerIndex);
      }

      setState(() {
        _loading = false;
        _title = (graph['title'] ?? widget.title ?? 'Graph').toString();
        _markdown = content;
      });
    } else {
      setState(() {
        _loading = false;
        _error = (result['error'] ?? 'Failed to load graph').toString();
      });
    }
  }

  Future<void> _openLink(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied to clipboard'),
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  Map<String, MarkdownElementBuilder> _markdownBuilders(BuildContext context) {
    final linkColor = Theme.of(context).colorScheme.primary;
    return {
      'a': _CopyLinkBuilder(
        linkColor: linkColor,
        onTapHref: (href) {
          if (href == null || href.trim().isEmpty) return;
          _openLink(href);
        },
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final title = _title.trim().isEmpty ? 'Graph Viewer' : _title.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadGraph,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadGraph,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : Markdown(
              data: _markdown,
              selectable: true,
              builders: _markdownBuilders(context),
              onTapLink: (text, href, title) {
                // Intentionally do nothing here.
                // We override <a> via builders to prevent any in-app browser overlay.
              },
            ),
    );
  }
}

class _CopyLinkBuilder extends MarkdownElementBuilder {
  final Color linkColor;
  final void Function(String? href) onTapHref;

  _CopyLinkBuilder({required this.linkColor, required this.onTapHref});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final href = element.attributes['href'];
    final text = element.textContent;
    final style = (preferredStyle ?? const TextStyle()).copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
    );

    return InkWell(
      onTap: () => onTapHref(href),
      child: Text(text, style: style),
    );
  }
}
