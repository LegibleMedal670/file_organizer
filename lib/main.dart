import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:excel/excel.dart' as e;
import 'package:csv/csv.dart';
import 'package:libre_doc_converter/libre_doc_converter.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:syncfusion_flutter_pdf/pdf.dart';

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

  bool _isUploading = false;
  String _uploadStatus = "파일을 드래그 앤 드롭하거나 선택하세요.";

  Future<String> extractFirstNPages({
    required String inputFilePath,
    required String outputFilePath,
    required int nPages,
  }) async {
    // 1) 원본 PDF 불러오기
    //    (로컬 파일 시스템에서 읽어올 때는 File(...).readAsBytesSync() 사용)
    final List<int> originalBytes = File(inputFilePath).readAsBytesSync();
    final PdfDocument originalPdf = PdfDocument(inputBytes: originalBytes);

    // 2) 새 PdfDocument 생성
    final PdfDocument newPdf = PdfDocument();

    // 3) 앞 nPages 만큼 페이지 복사
    int total = originalPdf.pages.count;
    int pagesToCopy = (nPages > total) ? total : nPages;

    for (int i = 0; i < pagesToCopy; i++) {
      // PdfPageBase page = originalPdf.pages[i]; // 페이지 객체
      // 페이지를 통째로 import 해서 복사
      newPdf.pages.add().graphics.drawPdfTemplate(
        originalPdf.pages[i].createTemplate(),
        Offset(0, 0),
        // 원본 페이지 크기에 맞추기
        Size(originalPdf.pages[i].size.width, originalPdf.pages[i].size.height),
      );
    }

    // 4) 결과를 바이트로 저장
    final List<int> bytes = await newPdf.save();
    newPdf.dispose();
    originalPdf.dispose();

    // 5) 디스크에 쓰기
    File(outputFilePath).writeAsBytesSync(bytes);

    return outputFilePath;
  }

  Future<void> _uploadFiles() async {
    if (_droppedFiles.isEmpty) {
      setState(() {
        _uploadStatus = "업로드할 파일이 없습니다.";
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = "파일 업로드 전처리 중...";
    });

    // 1) 변환된 파일들만 담을 리스트를 만듭니다.
    List<File> processedFiles = [];

    // 2) 컨테이너 내부 임시 저장 디렉토리 경로를 가져옵니다.
    final tempDir = await getApplicationDocumentsDirectory();
    // 3) 시스템 전체 임시 디렉토리 (컨테이너 샌드박스 회피용)
    final sysTemp = Directory.systemTemp;

    for (var original in _droppedFiles) {
      final ext = original.path.split('.').last.toLowerCase();
      final baseName = path.basenameWithoutExtension(original.path);

      if (ext == 'xlsx') {
        // --- XLSX → CSV 변환 로직 ---
        try {
          final bytes = await original.readAsBytes();
          final excel = e.Excel.decodeBytes(bytes);

          // 모든 시트의 행 데이터를 2차원 리스트로 수집
          List<List<dynamic>> rows = [];
          for (var sheetName in excel.tables.keys) {
            final sheet = excel.tables[sheetName]!;
            for (var row in sheet.rows) {
              rows.add(row);
            }
          }

          // CSV 문자열로 변환
          String csvData = const ListToCsvConverter().convert(rows);

          // 컨테이너 내부 임시 경로에 저장 (예: ".../basename.csv")
          final csvPath = path.join(tempDir.path, '$baseName.csv');
          final csvFile = File(csvPath);
          await csvFile.writeAsString(csvData);

          print('CSV 변환 성공');

          processedFiles.add(csvFile);
        } catch (e) {
          // 변환 실패 시 원본 XLSX를 그대로 업로드 리스트에 추가
          processedFiles.add(original);
          print('XLSX → CSV 변환 오류 ($ext): $e');
        }
      } else if (ext == 'docx' || ext == 'pptx') {
        // --- DOCX/PPTX → PDF 변환 로직 (시스템 tmp 사용, Process.run) ---
        try {
          // 1) 컨테이너 내부 파일을 시스템 tmp로 복사
          final sysInputPath = path.join(sysTemp.path, '$baseName.$ext');
          final sysInputFile = await File(
            sysInputPath,
          ).writeAsBytes(await original.readAsBytes());

          print(sysInputFile);

          final converter = LibreDocConverter(inputFile: sysInputFile);

          //
          final sysPdfFile = await converter.toPdf();

          print(sysPdfFile.path);

          // 4) 컨테이너 내부 임시 디렉토리로 변환된 PDF를 복사
          final containerPdfPath = path.join(tempDir.path, '$baseName.pdf');
          final containerPdfFile = await File(
            containerPdfPath,
          ).writeAsBytes(await sysPdfFile.readAsBytes());

          processedFiles.add(containerPdfFile);

          print('PDF변환 성공');

          // 5) 시스템 tmp에 생성된 파일 정리 (선택 사항)
          if (await sysInputFile.exists()) await sysInputFile.delete();
          if (await sysPdfFile.exists()) await sysPdfFile.delete();
        } catch (e) {
          // 변환 실패 시 원본을 그대로 추가
          processedFiles.add(original);
          print('$ext → PDF 변환 오류: $e');
        }
      } else {
        // 그 외 확장자는 변환 없이 그대로 추가
        processedFiles.add(original);
      }
    }

    // 4) CSV 파일에서 앞 20줄만 추출하여 업로드용 리스트 준비
    List<File> uploadFiles = [];
    for (var file in processedFiles) {
      final ext = file.path.split('.').last.toLowerCase();
      final baseName = path.basenameWithoutExtension(file.path);

      if (ext == 'csv') {
        // --- CSV 파일에서 맨 앞 20줄만 추출 ---
        try {
          final allLines = await file.readAsLines();
          final trimmedLines = allLines.take(20).toList();
          final trimmedText = trimmedLines.join('\n');

          final trimmedPath = path.join(
            tempDir.path,
            '${baseName}_trimmed.txt',
          );
          final trimmedFile = File(trimmedPath);
          await trimmedFile.writeAsString(trimmedText);

          print(trimmedText);

          uploadFiles.add(trimmedFile);
        } catch (e) {
          // 트리밍 또는 텍스트 변환 실패 시 원본 CSV를 업로드
          uploadFiles.add(file);
          print('CSV 트리밍 및 텍스트 변환 오류: $e');
        }
      } else if (ext == 'pdf') {
        try {
          final String originalPdfPath = file.path;
          final String extractPdfPath = path.join(
            tempDir.path,
            '${baseName}.pdf',
          );

          final String pdfPath = await extractFirstNPages(
            inputFilePath: originalPdfPath,
            outputFilePath: extractPdfPath,
            nPages: 5,
          );

          final pdfFile = File(pdfPath);

          print('PDF 자르기 성공');

          uploadFiles.add(pdfFile);
        } catch (e) {
          uploadFiles.add(file);
          print('PDF 자르기 오류: $e');
        }
      } else {
        // PDF나 기타 파일은 그대로 업로드
        uploadFiles.add(file);
      }
    }

    // 5) 변환 및 트리밍 완료 후 상태 업데이트
    setState(() {
      _uploadStatus = "파일 업로드 준비 완료: ${uploadFiles.length}개 파일";
    });

    // 6) 실제 백엔드로 전송
    setState(() {
      _uploadStatus = "파일 업로드 중...";
    });
    final String backendUrl = 'http://172.25.86.197:8000/upload_and_classify';

    try {
      var request = http.MultipartRequest('POST', Uri.parse(backendUrl));

      for (var file in uploadFiles) {
        final ext = file.path.split('.').last.toLowerCase();
        String mimeType = 'application/octet-stream';

        if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
          mimeType = 'image/$ext';
        } else if (ext == 'pdf') {
          mimeType = 'application/pdf';
        } else if (ext == 'docx') {
          mimeType =
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        } else if (ext == 'xlsx') {
          mimeType =
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        } else if (ext == 'csv') {
          mimeType = 'text/csv';
        } else if (ext == 'txt') {
          mimeType = 'text/plain';
        } else if (ext == 'pptx') {
          mimeType =
              'application/vnd.openxmlformats-officedocument.presentationml.presentation';
        }

        request.files.add(
          await http.MultipartFile.fromPath(
            'files',
            file.path,
            filename: path.basename(file.path),
            contentType: MediaType.parse(mimeType),
          ),
        );
      }

      var responseStream = await request.send();
      var response = await http.Response.fromStream(responseStream);

      if (response.statusCode == 200) {
        setState(() {
          _uploadStatus = "파일 요약 완료: ${response.body}";
          print(response.body);
          _droppedFiles.clear();
        });
      } else {
        setState(() {
          _uploadStatus =
              "파일 업로드 실패: ${response.statusCode} - ${response.body}";
          _droppedFiles.clear();
          print(response.body);
        });
      }
    } catch (e) {
      setState(() {
        print(e);
        _droppedFiles.clear();
        _uploadStatus = "오류 발생: $e";
      });
    } finally {
      setState(() {
        _droppedFiles.clear();
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF323232),
      body: Row(
        children: [
          if (_droppedFiles.isNotEmpty && !_isUploading)
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
                      onPressed: _isUploading ? null : _uploadFiles,
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
                      _isUploading
                          ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Transform.scale(
                                scale: 1.5,
                                child: CircularProgressIndicator(
                                  color: const Color(0xFF005DC2),
                                ),
                              ),
                              SizedBox(height: 15),
                              Text(
                                _uploadStatus,
                                style: TextStyle(
                                  color: Color(0xFFAAAAAA),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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
}
