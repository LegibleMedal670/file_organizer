import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FileOrganizerApp());
}

class FileOrganizerApp extends StatelessWidget {
  const FileOrganizerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'File Organizer',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const OrganizerHomePage(),
    );
  }
}

class OrganizerHomePage extends StatefulWidget {
  const OrganizerHomePage({Key? key}) : super(key: key);

  @override
  State<OrganizerHomePage> createState() => _OrganizerHomePageState();
}

class _OrganizerHomePageState extends State<OrganizerHomePage> {
  final List<File> _droppedFiles = [];
  bool _dragging = false;
  final List<String> _allowedExtension = [
    'jpg',
    'png',
    'pdf',
    'docx',
    'pptx',
    'txt',
    'webp',
    'csv',
    'xlsx',
    'jpeg',
  ];

  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF323232),
      body: Row(
        children: [
          if (_droppedFiles.isNotEmpty)
            Expanded(
              flex: 1,
              child: Container(
                color: Colors.grey[100],
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Dropped Files',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_droppedFiles.length}/10',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _droppedFiles.length,
                        itemBuilder: (context, index) {
                          final file = _droppedFiles[index];
                          final ext = file.path.split('.').last.toLowerCase();
                          FaIcon icon;
                          switch (ext) {
                            case 'pdf':
                              icon = const FaIcon(FontAwesomeIcons.filePdf);
                              break;
                            case 'jpg':
                            case 'png':
                            case 'webp':
                            case 'jpeg':
                              icon = const FaIcon(FontAwesomeIcons.fileImage);
                              break;
                            case 'docx':
                              icon = const FaIcon(FontAwesomeIcons.fileWord);
                              break;
                            case 'pptx':
                              icon = const FaIcon(
                                FontAwesomeIcons.filePowerpoint,
                              );
                              break;
                            case 'xlsx':
                              icon = const FaIcon(FontAwesomeIcons.fileExcel);
                              break;
                            case 'csv':
                              icon = const FaIcon(FontAwesomeIcons.fileCsv);
                              break;
                            default:
                              icon = const FaIcon(FontAwesomeIcons.file);
                          }
                          return ListTile(
                            leading: icon,
                            title: Text(
                              file.path.split(Platform.pathSeparator).last,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(() {
                                  _droppedFiles.removeAt(index);
                                });
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: FaIcon(
                                  FontAwesomeIcons.xmark,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: (){
                        print('asd');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF005DC2),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 6,
                        shadowColor: Colors.black45,
                      ),
                      child: const Text(
                        'Execute',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: DropTarget(
                onDragEntered: (_) => setState(() => _dragging = true),
                onDragExited: (_) => setState(() => _dragging = false),
                onDragDone: (detail) {
                  bool exceeded = false;
                  setState(() {
                    _dragging = false;
                    for (var d in detail.files) {
                      if (_droppedFiles.length >= 10) {
                        exceeded = true;
                        break;
                      }
                      final p = d.path;
                      if (p == null) continue;
                      final e = p.split('.').last.toLowerCase();
                      if (!_droppedFiles.any((f) => f.path == p) &&
                          _allowedExtension.contains(e)) {
                        _droppedFiles.add(File(p));
                      }
                    }
                  });
                  if (exceeded) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('최대 10개까지만 추가할 수 있습니다.')),
                    );
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF323232),
                    border: Border.all(
                      color: const Color(0xFFAAAAAA),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      _isLoading
                          ? Center(
                            child: Transform.scale(
                              scale: 1.5,
                              child: CircularProgressIndicator(
                                color: const Color(0xFF005DC2),
                              ),
                            ),
                          )
                          : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.file_open_outlined,
                                size: 70,
                                color:
                                    _dragging
                                        ? const Color(0xFF005DC2)
                                        : const Color(0xFFAAAAAA),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Drag & Drop Files Here',
                                style: TextStyle(
                                  color:
                                      _dragging
                                          ? const Color(0xFF005DC2)
                                          : const Color(0xFFAAAAAA),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Future<void> _showCategoryDialog() async {
  //   String? selected;
  //   String custom = '';
  //   await showDialog(
  //     context: context,
  //     barrierColor: Colors.black54,
  //     builder: (ctx) {
  //       return StatefulBuilder(
  //         builder: (BuildContext context, StateSetter conceptState) {
  //           return Dialog(
  //             shape: RoundedRectangleBorder(
  //               borderRadius: BorderRadius.circular(16),
  //             ),
  //             elevation: 12,
  //             backgroundColor: Colors.white,
  //             child: SizedBox(
  //               width: 400,
  //               child: Padding(
  //                 padding: const EdgeInsets.all(24),
  //                 child: Column(
  //                   mainAxisSize: MainAxisSize.min,
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     const Text(
  //                       'Select Concept',
  //                       style: TextStyle(
  //                         fontSize: 20,
  //                         fontWeight: FontWeight.bold,
  //                       ),
  //                     ),
  //                     const SizedBox(height: 16),
  //                     Wrap(
  //                       spacing: 12,
  //                       runSpacing: 12,
  //                       children:
  //                           ['School', 'Project', 'Company', 'ETC']
  //                               .map(
  //                                 (label) => ChoiceChip(
  //                                   label: Text(label),
  //                                   selected: selected == label,
  //                                   selectedColor: const Color(0xFF005DC2),
  //                                   backgroundColor: const Color(0xFFF0F0F0),
  //                                   labelStyle: TextStyle(
  //                                     color:
  //                                         selected == label
  //                                             ? Colors.white
  //                                             : Colors.black87,
  //                                   ),
  //                                   onSelected: (v) {
  //                                     conceptState(() {
  //                                       selected = v ? label : null;
  //                                       // clear custom when switching off ETC
  //                                       if (selected != 'ETC') custom = '';
  //                                     });
  //                                   },
  //                                   shape: RoundedRectangleBorder(
  //                                     borderRadius: BorderRadius.circular(8),
  //                                   ),
  //                                 ),
  //                               )
  //                               .toList(),
  //                     ),
  //                     if (selected == 'ETC') ...[
  //                       const SizedBox(height: 16),
  //                       TextField(
  //                         decoration: InputDecoration(
  //                           filled: true,
  //                           fillColor: const Color(0xFFF7F7F7),
  //                           hintText: 'Enter custom concept',
  //                           border: OutlineInputBorder(
  //                             borderRadius: BorderRadius.circular(8),
  //                             borderSide: BorderSide.none,
  //                           ),
  //                         ),
  //                         onChanged:
  //                             (v) => conceptState(() {
  //                               custom = v;
  //                             }),
  //                       ),
  //                     ],
  //                     const SizedBox(height: 24),
  //                     Row(
  //                       mainAxisAlignment: MainAxisAlignment.end,
  //                       children: [
  //                         TextButton(
  //                           onPressed: () => Navigator.pop(ctx),
  //                           style: TextButton.styleFrom(
  //                             foregroundColor: Colors.black54,
  //                           ),
  //                           child: const Text('Cancel'),
  //                         ),
  //                         const SizedBox(width: 12),
  //                         ElevatedButton(
  //                           onPressed:
  //                               (selected == null ||
  //                                       (selected == 'ETC' && custom.isEmpty))
  //                                   ? null
  //                                   : () async {
  //                                     final concept =
  //                                         selected == 'ETC' ? custom : selected;
  //                                     // TODO: handle selected concept
  //
  //                                     print(concept);
  //
  //                                     setState(() {
  //                                       _droppedFiles.clear();
  //
  //                                       _isLoading = true;
  //                                     });
  //
  //                                     Navigator.pop(ctx, concept);
  //
  //                                     await Future.delayed(
  //                                       Duration(milliseconds: 1500),
  //                                     );
  //
  //                                     setState(() {
  //                                       _isLoading = false;
  //                                     });
  //                                   },
  //                           style: ElevatedButton.styleFrom(
  //                             backgroundColor: const Color(0xFF005DC2),
  //                             elevation: 6,
  //                             shape: RoundedRectangleBorder(
  //                               borderRadius: BorderRadius.circular(8),
  //                             ),
  //                             minimumSize: const Size(80, 40),
  //                           ),
  //                           child: const Text(
  //                             'OK',
  //                             style: TextStyle(color: Colors.white),
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ),
  //           );
  //         },
  //       );
  //     },
  //   );
  // }
}
