import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
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
  List<String> _uploadStatusList = [];
  bool _showResultButton = false;
  bool _showMarkDown = false;
  String _markdownSummary = '';

  /// 원본 파일명(확장자 포함) -> 원본 파일 전체 경로를 저장
  final Map<String, String> _originalPathMap = {};

  /// 파일 전처리 업로드 후처리

  Future<String> extractFirstNPages({
    required String inputFilePath,
    required String outputFilePath,
    required int nPages,
  }) async {
    // 1) 원본 PDF 불러오기
    final List<int> originalBytes = File(inputFilePath).readAsBytesSync();
    final PdfDocument originalPdf = PdfDocument(inputBytes: originalBytes);

    // 2) 결과를 담을 새로운 PdfDocument 생성
    final PdfDocument newPdf = PdfDocument();

    // 3) 앞 nPages 만큼만 복사하기
    int totalPages = originalPdf.pages.count;
    int pagesToCopy = (nPages > totalPages) ? totalPages : nPages;

    for (int pageIndex = 0; pageIndex < pagesToCopy; pageIndex++) {
      // 3-1) 원본 페이지 객체
      PdfPage originalPage = originalPdf.pages[pageIndex];

      // 3-2) 원본 페이지의 Size(폭, 높이) 정보를 가져온다
      Size originalSize = originalPage.size;

      // 3-3) 새 페이지를 만들 때, 반드시 원본 페이지 크기를 그대로 지정
      // newPdf.pages.add(Size) 오버로드가 없는 경우에는 아래처럼 pageSettings로 지정 후 add()
      newPdf.pageSettings.size = originalSize;

      // print('$inputFilePath\'s height: ${originalSize.height}, width: ${originalSize.width}');

      newPdf.pageSettings.orientation =
          originalSize.width >= originalSize.height
              ? PdfPageOrientation.landscape
              : PdfPageOrientation.portrait;

      PdfPage newPage = newPdf.pages.add();

      // 3-4) 원본 페이지 전체를 하나의 템플릿 객체로 만든다
      // 최신 버전에서는 createTemplate()가 PdfTemplate을 반환한다.
      PdfTemplate template = originalPage.createTemplate();

      // 3-5) 새 페이지의 (0,0) 좌표에 원본 크기만큼 그대로 그린다
      newPage.graphics.drawPdfTemplate(
        template,
        Offset(0, 0),
        Size(originalSize.width, originalSize.height),
      );
    }

    // 4) 새로운 PDF를 바이트 배열로 저장
    final List<int> newBytes = await newPdf.save();
    newPdf.dispose();
    originalPdf.dispose();

    // 5) 디스크에 쓰기
    File(outputFilePath).writeAsBytesSync(newBytes);

    return outputFilePath;
  }

  Future<void> _uploadFiles() async {
    if (_droppedFiles.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('업로드할 파일이 없습니다.')));
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatusList.clear();
      _uploadStatusList.add("파일 업로드 전처리 중...");
    });

    // -----------------------
    // 1) ★ 원본 파일명 → 원본 경로 매핑 저장
    //    (여기서는 아직 전처리 전이므로, 단순히 원본만 매핑)
    _originalPathMap.clear();
    for (var file in _droppedFiles) {
      final originalName = path.basename(
        file.path,
      ); // ex: "3장 계획.pdf" 또는 "과제.docx"
      _originalPathMap[originalName] = file.path;
    }
    // -----------------------

    // 2) ★ 전처리 파일명 → 원본 파일 경로 매핑 테이블
    //    (이후 서버 응답에 나오는 전처리된 이름으로 원본을 찾아가기 위함)
    final Map<String, String> processedToOriginalMap = {};

    // 3) 전처리된 파일 객체들만 모아둘 리스트
    List<File> processedFiles = [];

    // ★ 생성된 임시 파일 경로 추적 리스트
    List<File> _tempCreatedFiles = [];

    // 4) 앱 전용 임시 디렉토리 & 시스템 임시 디렉토리
    final tempDir = await getApplicationDocumentsDirectory();
    final sysTemp = Directory.systemTemp;

    // ===== 전처리 루프 =====
    for (var original in _droppedFiles) {
      final ext =
          path.extension(original.path).replaceFirst('.', '').toLowerCase();
      final baseName = path.basenameWithoutExtension(original.path);

      if (ext == 'xlsx') {
        // --- XLSX → CSV 변환 ---
        try {
          final bytes = await original.readAsBytes();
          final excel = e.Excel.decodeBytes(bytes);

          List<List<dynamic>> rows = [];
          for (var sheetName in excel.tables.keys) {
            final sheet = excel.tables[sheetName]!;
            for (var row in sheet.rows) {
              rows.add(row);
            }
          }

          String csvData = const ListToCsvConverter().convert(rows);
          final csvPath = path.join(tempDir.path, '$baseName.csv');
          final csvFile = File(csvPath);
          await csvFile.writeAsString(csvData);
          _tempCreatedFiles.add(csvFile);

          // ★ 서버에 보낼 때는 이 CSV를 보내지만,
          //    "test.xlsx" → "test.csv"로 전처리된 이름을 매핑해서
          //    실제 이동 시에는 원본 XLSX를 사용하기 위함
          processedToOriginalMap[path.basename(csvFile.path)] = original.path;

          processedFiles.add(csvFile);
        } catch (e) {
          // 변환에 실패하면 원본 XLSX를 그대로 업로드 대상으로 추가
          processedFiles.add(original);
        }
      } else if (ext == 'docx' || ext == 'pptx') {
        // --- DOCX/PPTX → PDF 변환 ---
        try {
          // 1) 앱 내부(EX: tempDir)가 아닌 시스템 tmp로 복사
          final sysInputPath = path.join(sysTemp.path, '$baseName.$ext');
          final sysInputFile = await File(
            sysInputPath,
          ).writeAsBytes(await original.readAsBytes());

          // 2) LibreDocConverter로 PDF 변환 (시스템 tmp에 생성)
          final converter = LibreDocConverter(inputFile: sysInputFile);
          final sysPdfFile = await converter.toPdf();

          // 3) 변환된 PDF를 앱 전용 디렉토리로 복사
          final containerPdfPath = path.join(tempDir.path, '$baseName.pdf');
          final containerPdfFile = await File(
            containerPdfPath,
          ).writeAsBytes(await sysPdfFile.readAsBytes());
          _tempCreatedFiles.add(containerPdfFile);

          // ★ "test.docx" → "test.pdf"로 전처리된 이름 → 실제 이동 시 원본 DOCX를 사용
          processedToOriginalMap[path.basename(containerPdfFile.path)] =
              original.path;

          processedFiles.add(containerPdfFile);

          // 4) 시스템 tmp에 생성된 입력/출력 파일 삭제
          if (await sysInputFile.exists()) await sysInputFile.delete();
          if (await sysPdfFile.exists()) await sysPdfFile.delete();
        } catch (e) {
          // 변환 실패 시 원본 DOCX/PPTX를 그대로 업로드 대상으로 추가
          processedFiles.add(original);
        }
      } else {
        // 기타 확장자(이미지, PDF, txt 등)는 전처리 없이 그대로 업로드
        processedFiles.add(original);
      }
    }

    // ===== 리샘플링 단계: CSV, PDF 트리밍 등 =====
    List<File> uploadFiles = [];
    for (var file in processedFiles) {
      final ext = path.extension(file.path).replaceFirst('.', '').toLowerCase();
      final baseName = path.basenameWithoutExtension(file.path);

      if (ext == 'csv') {
        // --- CSV 앞 20줄만 추출 → .txt 생성 ---
        try {
          final linesStream = file
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter());
          final List<String> trimmedLines = [];
          await for (var line in linesStream) {
            trimmedLines.add(line);
            if (trimmedLines.length >= 20) break;
          }
          final trimmedText = trimmedLines.join('\n');

          final trimmedPath = path.join(
            tempDir.path,
            '${baseName}_trimmed.txt',
          );
          final trimmedFile = File(trimmedPath);
          await trimmedFile.writeAsString(trimmedText);
          _tempCreatedFiles.add(trimmedFile);

          // ★ "test.csv" → "test_trimmed.txt"로 전처리된 이름 → 실제 이동 시 원본 XLSX를 사용
          //   (CSV를 만든 원본이 originalMap["test.xlsx"], or processedToOriginalMap["test.csv"])
          //   원본 XLSX 경로를 찾기 위해 먼저 processedToOriginalMap["test.csv"]를 조회
          String? xlsxOrigin = processedToOriginalMap[path.basename(file.path)];
          if (xlsxOrigin != null) {
            processedToOriginalMap[path.basename(trimmedFile.path)] =
                xlsxOrigin;
          } else {
            // 만약 processedFiles에 CSV가 직접 들어왔다면, file.path가 원본 CSV일 수도 있다.
            final maybeCsvOriginal = _originalPathMap[path.basename(file.path)];
            if (maybeCsvOriginal != null) {
              processedToOriginalMap[path.basename(trimmedFile.path)] =
                  maybeCsvOriginal;
            }
          }

          uploadFiles.add(trimmedFile);
        } catch (e) {
          // 트리밍 실패 시 원본 CSV 그대로 업로드
          uploadFiles.add(file);
        }
      } else if (ext == 'pdf') {
        // --- PDF 첫 5페이지만 추출 → 새 PDF 생성 ---
        try {
          final originalPdfPath = file.path;
          final extractPdfPath = path.join(
            tempDir.path,
            '${baseName}_trimmed.pdf',
          );

          final pdfPath = await extractFirstNPages(
            inputFilePath: originalPdfPath,
            outputFilePath: extractPdfPath,
            nPages: 5,
          );
          final pdfFile = File(pdfPath);
          _tempCreatedFiles.add(pdfFile);

          // ★ "test.pdf" → "test_trimmed.pdf"로 전처리된 이름 → 실제 이동 시 원본 DOCX/PPTX를 사용
          //   (PDF를 만든 원본이 processedToOriginalMap["test.pdf"])
          final maybeDocxOrigin =
              processedToOriginalMap[path.basename(file.path)];
          if (maybeDocxOrigin != null) {
            processedToOriginalMap[path.basename(pdfFile.path)] =
                maybeDocxOrigin;
          } else {
            // 만약 file.path가 원본 PDF였다면 _originalPathMap에서 찾아본다
            final maybePdfOriginal = _originalPathMap[path.basename(file.path)];
            if (maybePdfOriginal != null) {
              processedToOriginalMap[path.basename(pdfFile.path)] =
                  maybePdfOriginal;
            }
          }

          uploadFiles.add(pdfFile);
        } catch (e) {
          uploadFiles.add(file);
        }
      } else {
        // 이미지, txt 또는 변환 실패로 포함된 원본 파일 등 → 그대로 업로드
        uploadFiles.add(file);
        // ★ 이 경우, _originalPathMap에 이미 매핑되어 있으므로 별도 조치 불필요
      }
    }

    setState(() {
      _uploadStatusList.clear();
      _uploadStatusList.add("파일 업로드 전처리 완료: ${processedFiles.length}개 파일");
      _uploadStatusList.add("파일 업로드 중...");
    });

    // 실제 배포시엔 백엔드 구성해서 사용
    final String backendUrl = 'http://172.25.86.197:8000/upload_and_classify';

    try {
      var request = http.MultipartRequest('POST', Uri.parse(backendUrl));

      for (var file in uploadFiles) {
        final ext =
            path.extension(file.path).replaceFirst('.', '').toLowerCase();
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

      setState(() {
        _uploadStatusList.remove("파일 업로드 중...");
        _uploadStatusList.add("파일 업로드 완료");
        _uploadStatusList.add("파일 정리 중...");
      });

      var responseStream = await request.send();
      var response = await http.Response.fromStream(responseStream);

      if (response.statusCode == 200) {
        print(response.body);

        // ============================
        // 7) ★ “전처리된 파일명 → 원본 파일 경로(원본 확장자 그대로)”를
        //       _originalPathMap에 병합
        processedToOriginalMap.forEach((procName, origPath) {
          // ex) key = "testDocx_trimmed.pdf", value = "/Users/.../Desktop/testDocx.docx"
          _originalPathMap[procName] = origPath;
        });
        // ============================

        try {
          final Map<String, dynamic> jsonResp =
              jsonDecode(response.body) as Map<String, dynamic>;
          final orgSpec = jsonResp['organization_spec'] as Map<String, dynamic>;

          // 8) 최상위 이동 폴더 생성 (바탕화면 '정리된 폴더' 하나만)
          String desktopDir;
          if (Platform.isWindows) {
            // Windows라면 USERPROFILE/Desktop
            desktopDir = path.join(
              Platform.environment['USERPROFILE']!,
              'Desktop',
            );
          } else {
            // macOS/Linux라면 HOME/Desktop
            desktopDir = path.join(Platform.environment['HOME']!, 'Desktop');
          }

          final String rootDirPath = path.join(desktopDir, '정리된 폴더');
          final Directory rootDir = Directory(rootDirPath);
          if (!rootDir.existsSync()) {
            rootDir.createSync(recursive: true);
          }

          // 9) 폴더 구조대로 원본 파일 이동
          createFoldersAndMoveFiles(orgSpec, rootDirPath, _originalPathMap);

          setState(() {
            _uploadStatusList.remove("파일 정리 중...");
            _uploadStatusList.add("파일 정리 완료");
            _showResultButton = true;
            _markdownSummary = jsonResp['markdown_summary'] as String;
          });
        } catch (e) {
          print(e);
        }

        setState(() {
          _droppedFiles.clear();
        });
      } else {
        setState(() {
          print("파일 업로드 실패: ${response.statusCode} - ${response.body}");
          _droppedFiles.clear();
        });
      }
    } catch (e) {
      setState(() {
        _droppedFiles.clear();
        print("오류 발생: $e");
      });
    } finally {
      // 10) ★ 임시 파일들 삭제
      for (var tempFile in _tempCreatedFiles) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e) {
          print('임시 파일 삭제 중 오류: $e');
        }
      }
    }
  }

  void createFoldersAndMoveFiles(
    Map<String, dynamic> spec,
    String currentPath,
    Map<String, String> originalMap,
  ) {
    spec.forEach((key, value) {
      // 1) 현재 레벨에서 생성할 폴더 경로
      final String folderPath = path.join(currentPath, key);
      final Directory dir = Directory(folderPath);

      // 폴더가 없으면 생성
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      if (value is List) {
        // value가 List라면 “파일 이름 리스트”로 간주 (processedName 들)
        for (var processedName in value) {
          if (processedName is String &&
              originalMap.containsKey(processedName)) {
            final String originalPath = originalMap[processedName]!;
            final File origFile = File(originalPath);

            // ★ 원본 파일명 그대로 유지하기 위해, 원본 경로에서 basename을 꺼냄
            final String originalFileName = path.basename(originalPath);
            final String newPath = path.join(folderPath, originalFileName);

            try {
              if (origFile.existsSync()) {
                try {
                  // 같은 디스크 내 이동: renameSync
                  origFile.renameSync(newPath);
                } catch (_) {
                  // 크로스 디바이스 등으로 renameSync 실패 시 복사 + 삭제
                  origFile.copySync(newPath);
                  origFile.deleteSync();
                }
              }
            } catch (e) {
              print("파일 이동 오류 ($originalFileName): $e");
            }
          }
        }
      } else if (value is Map<String, dynamic>) {
        // value가 Map이면 하위 폴더가 있으므로 재귀 호출
        createFoldersAndMoveFiles(value, folderPath, originalMap);
      }
    });
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
                          '등록된 파일',
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
                        '정리하기',
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
                      _showMarkDown
                          ? Column(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: SizedBox(
                                    width: 600,
                                    child: GptMarkdown(
                                      _markdownSummary,
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 100,
                                  right: 100,
                                  bottom: 10,
                                ),
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _showResultButton = false;
                                      _isUploading = false;
                                      _showMarkDown = false;
                                      _markdownSummary = '';
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF005DC2),
                                    minimumSize: const Size(
                                      double.infinity,
                                      44,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 6,
                                    shadowColor: Colors.black45,
                                  ),
                                  child: const Text(
                                    '확인',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                          : _isUploading
                          ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _showResultButton
                                  ? Padding(
                                    padding: const EdgeInsets.only(
                                      top: 160.0,
                                      bottom: 30.0,
                                    ),
                                    child: Icon(
                                      Icons.check_circle_outline,
                                      size: 80,
                                      color: Color(0xFF5CB85C),
                                    ),
                                  )
                                  : Padding(
                                    padding: const EdgeInsets.only(
                                      top: 160.0,
                                      bottom: 30.0,
                                    ),
                                    child: Transform.scale(
                                      scale: 1.5,
                                      child: CircularProgressIndicator(
                                        color: const Color(0xFF005DC2),
                                      ),
                                    ),
                                  ),
                              // 로그가 쌓이는 영역
                              SizedBox(
                                height: 150, // 필요에 따라 조절
                                child: ListView.builder(
                                  itemCount: _uploadStatusList.length,
                                  itemBuilder:
                                      (context, idx) => Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            _uploadStatusList[idx],
                                            style: const TextStyle(
                                              color: Color(0xFFAAAAAA),
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                              if (_showResultButton)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 100,
                                    right: 100,
                                    bottom: 10,
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _showResultButton = false;
                                        _isUploading = false;
                                        _showMarkDown = true;
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF005DC2),
                                      minimumSize: const Size(
                                        double.infinity,
                                        44,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 6,
                                      shadowColor: Colors.black45,
                                    ),
                                    child: const Text(
                                      '정리 요약 보기',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
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
