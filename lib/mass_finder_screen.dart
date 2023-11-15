import 'dart:isolate';

import 'package:mass_finder/util/alert_toast.dart';
import 'package:mass_finder/helper/mass_finder_helper.dart';
import 'package:mass_finder/model/amino_model.dart';
import 'package:mass_finder/widget/amino_map_selector.dart';
import 'package:mass_finder/widget/formylation_selector.dart';
import 'package:mass_finder/widget/loading_overlay.dart';
import 'package:mass_finder/widget/normal_text_field.dart';
import 'package:flutter/material.dart';

class MassFinderScreen extends StatefulWidget {
  const MassFinderScreen({Key? key}) : super(key: key);

  @override
  State<MassFinderScreen> createState() => _MassFinderScreenState();
}

class _MassFinderScreenState extends State<MassFinderScreen> {
  TextEditingController targetWeight = TextEditingController();
  TextEditingController targetSize = TextEditingController();
  TextEditingController initAmino = TextEditingController();

  double get _targetWeight => textToDouble(targetWeight.text);

  List<AminoModel> resultList = [];

  final _receivePort = ReceivePort();
  bool isLoading = false;

  static double? totalWeight;

  FormyType currentFormyType = FormyType.unknown;

  // 계산시에 사용할 아미노산 리스트 , 최초에는 모든 아미노산을 포함한다.
  Map<String, int> inputAminos = Map.from(aminoMap);

  @override
  void initState() {
    super.initState();
    _receivePort.listen((message) {
      setState(() {
        var mapList = message as List<Map<String, dynamic>>;
        resultList = mapList.map((e) => AminoModel.fromJson(e)).toList();
        isLoading = false;
      });
    });

    targetWeight.addListener(() {
      totalWeight = _targetWeight * 100;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: LoadingOverlay(
            color: Colors.black12,
            isLoading: isLoading,
            child: SelectionArea(child: Center(child: _buildBody())),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Container(
      padding: const EdgeInsets.all(40),
      constraints: const BoxConstraints(
        maxWidth: 500,
        minWidth: 300,
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Text(
              'Mass finder',
              style: TextStyle(fontSize: 20, color: Colors.black),
            ),
            const SizedBox(height: 10),
            NormalTextField(
              textController: targetWeight,
              labelText: 'Exact Mass', // 총 단백질의 무게
              digitOnly: false,
              hintText: 'please enter exact mass(only digit)', // 숫자만 입력
            ),
            const SizedBox(height: 10),
            NormalTextField(
              textController: initAmino,
              labelText: 'Essential Sequence (Option)',
              hintText: 'please enter essential sequence (olny alphabet)',
            ),
            const SizedBox(height: 10),
            // f 있는지 여부
            FormylationSelector(
              fomyType: currentFormyType,
              onChange: (newType) {
                setState(() {
                  currentFormyType = newType;
                });
              },
            ),
            // 아미노산 종류 선택부분
            AminoMapSelector(
              onChangeAminos: (aminos) {
                var selectedAminos = Map.from(aminos);
                selectedAminos.removeWhere((k, v) => v == false);
                inputAminos.clear();
                for (var e in selectedAminos.keys) {
                  inputAminos[e] = aminoMap[e] ?? 0;
                }
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => onTapCalc(context),
              child: Container(
                width: double.infinity,
                height: 50,
                alignment: Alignment.center,
                child: const Text('Calcualtion!'),
              ),
            ),
            const SizedBox(height: 10),
            _aminoList(),
          ],
        ),
      ),
    );
  }

  Widget _aminoList() {
    return ListView.builder(
      itemCount: resultList.length,
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemBuilder: (_, index) {
        return _exampleListItem(resultList[index]);
      },
    );
  }

  Widget _exampleListItem(AminoModel item) {
    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sequence : ${item.code}'),
          // Text('물 증발 전 무게 : ${item.totalWeight}'),
          // Text('물 증발량 : ${item.waterWeight}'),
          Text('Exact Mass : ${item.weight}'),
        ],
      ),
    );
  }

  double textToDouble(String value) {
    var convert = double.tryParse(value);
    if (convert == null) {
      print('계산에 오류가 발생했습니다.');
      // Fluttertoast.showToast(msg: '계산에 오류가 발생했습니다.');
      return 1.0;
    }
    return convert;
  }

  int textToInt(String value) {
    var convert = int.tryParse(value);
    if (convert == null) {
      print('계산에 오류가 발생했습니다.');
      // Fluttertoast.showToast(msg: '계산에 오류가 발생했습니다.');
      return 1;
    }
    return convert;
  }

  /// 계산하기 클릭 이벤트
  Future<void> onTapCalc(BuildContext context) async {
    if(validate(context) == false) return;
    resultList.clear();
    isLoading = true;
    setState(() {});
    double w = totalWeight ?? 0.0;
    String a = initAmino.text;
    String f = currentFormyType.text;
    Map<String, int> ia = inputAminos;
    try {
      Isolate.spawn<SendPort>(
        (sp) => MassFinderHelper.calc(sp, w, a, f, ia),
        _receivePort.sendPort,
      );
    } catch (e) {
      AlertToast.show(context: context, msg: 'error occurred!!');
    }
  }

  // 계산 시작전 각종 조건을 체크하는 부분
  bool validate(BuildContext context){
    String? validText = getValidateMsg();
    if(validText == null) return true;
    AlertToast.show(msg: validText, context: context);
    return false;
  }

  // 실제 각 조건별 메세지를 셋팅하는 부분
  String? getValidateMsg(){
    String? msg;
    // 체크박스에 포함되지 않은값을 초기값으로 넣으려고 할때
    String initAminoText = initAmino.text;
    initAminoText.split('').forEach((e) {
      if(inputAminos[e] == null){
        msg = '체크박스에 포함되어있지 않은 값이 Essential Sequence에 들어있음';
      }
    });
    // exact mass 값을 안넣었을때
    if (totalWeight == null) {
      msg = 'please enter extra mass!';
    }
    return msg;
  }
}

/// 아미노산들의 리스트
final aminoMap = {
  'G': 7503,
  'A': 8905,
  'S': 10504,
  'T': 11906,
  'C': 12102,
  'V': 11708,
  'L': 13109,
  'I': 13109,
  'M': 14905,
  'P': 11506,
  'F': 16508,
  'Y': 18107,
  'W': 20409,
  'D': 13304,
  'E': 14705,
  'N': 13205,
  'Q': 14607,
  'H': 15507,
  'K': 14611,
  'R': 17411,
};
