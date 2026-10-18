import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'player_service.dart';
import 'settings_service.dart';

/// Single line of synchronized lyrics.
class LyricLine {
  final Duration timestamp;
  final String text;
  final String? romanizedText;
  final String? translationText;

  const LyricLine({
    required this.timestamp,
    required this.text,
    this.romanizedText,
    this.translationText,
  });

  LyricLine copyWith({
    Duration? timestamp,
    String? text,
    String? romanizedText,
    String? translationText,
  }) {
    return LyricLine(
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      romanizedText: romanizedText ?? this.romanizedText,
      translationText: translationText ?? this.translationText,
    );
  }

  @override
  String toString() => '[${timestamp.inSeconds}s] $text ($romanizedText) [$translationText]';
}

/// Parsed lyrics bundle for a track.
class LyricsData {
  final List<LyricLine> lines;
  final bool isSynced;
  final bool hasForeign;
  final String? source;
  final Map<String, LyricsData> providerVariants;

  const LyricsData({
    required this.lines,
    this.isSynced = true,
    this.hasForeign = false,
    this.source,
    this.providerVariants = const {},
  });

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  LyricsData copyWith({
    List<LyricLine>? lines,
    bool? isSynced,
    bool? hasForeign,
    String? source,
    Map<String, LyricsData>? providerVariants,
  }) {
    return LyricsData(
      lines: lines ?? this.lines,
      isSynced: isSynced ?? this.isSynced,
      hasForeign: hasForeign ?? this.hasForeign,
      source: source ?? this.source,
      providerVariants: providerVariants ?? this.providerVariants,
    );
  }
}

/// Offline romanization engine for Japanese (Romaji), Korean (Romaja / RR), and Cyrillic.
class LyricsRomanizer {
  // Korean Hangul Jamo tables
  static const List<String> _koreanInitials = [
    'g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', 'ss', '',
    'j', 'jj', 'ch', 'k', 't', 'p', 'h'
  ];

  static const List<String> _koreanVowels = [
    'a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae', 'oe',
    'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i'
  ];

  static const List<String> _koreanFinals = [
    '', 'k', 'k', 'ks', 'n', 'nj', 'nh', 't', 'l', 'lg', 'lm', 'lb', 'ls', 'lt',
    'lp', 'lh', 'm', 'p', 'ps', 't', 't', 'ng', 't', 't', 'k', 't', 'p', 'h'
  ];

  // Korean standalone compatibility Jamo
  static const Map<int, String> _koreanJamo = {
    0x3131: 'k', 0x3132: 'kk', 0x3133: 'ks', 0x3134: 'n', 0x3137: 't',
    0x3138: 'tt', 0x3139: 'r', 0x3141: 'm', 0x3142: 'p', 0x3143: 'pp',
    0x3145: 's', 0x3146: 'ss', 0x3147: 'ng', 0x3148: 'j', 0x3149: 'jj',
    0x314A: 'ch', 0x314B: 'k', 0x314C: 't', 0x314D: 'p', 0x314E: 'h',
    0x314F: 'a', 0x3150: 'ae', 0x3151: 'ya', 0x3152: 'yae', 0x3153: 'eo',
    0x3154: 'e', 0x3155: 'yeo', 0x3156: 'ye', 0x3157: 'o', 0x3158: 'wa',
    0x3159: 'wae', 0x315A: 'oe', 0x315B: 'yo', 0x315C: 'u', 0x315D: 'wo',
    0x315E: 'we', 0x315F: 'wi', 0x3160: 'yu', 0x3161: 'eu', 0x3162: 'ui',
    0x3163: 'i',
  };

  // Japanese Kana table
  static const Map<String, String> _kanaMap = {
    'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
    'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
    'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
    'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
    'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
    'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
    'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
    'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
    'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro',
    'わ': 'wa', 'を': 'wo', 'ん': 'n',
    'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
    'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
    'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
    'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
    'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
    'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo',
    'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho',
    'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho',
    'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
    'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo',
    'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
    'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',
    'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
    'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo',
    'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
    'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo',
    // Katakana
    'ア': 'a', 'イ': 'i', 'ウ': 'u', 'エ': 'e', 'オ': 'o',
    'カ': 'ka', 'キ': 'ki', 'ク': 'ku', 'ケ': 'ke', 'コ': 'ko',
    'サ': 'sa', 'シ': 'shi', 'ス': 'su', 'セ': 'se', 'ソ': 'so',
    'タ': 'ta', 'チ': 'chi', 'ツ': 'tsu', 'テ': 'te', 'ト': 'to',
    'ナ': 'na', 'ニ': 'ni', 'ヌ': 'nu', 'ネ': 'ne', 'ノ': 'no',
    'ハ': 'ha', 'ヒ': 'hi', 'フ': 'fu', 'ヘ': 'he', 'ホ': 'ho',
    'マ': 'ma', 'ミ': 'mi', 'ム': 'mu', 'メ': 'me', 'モ': 'mo',
    'ヤ': 'ya', 'ユ': 'yu', 'ヨ': 'yo',
    'ラ': 'ra', 'リ': 'ri', 'ル': 'ru', 'レ': 're', 'ロ': 'ro',
    'ワ': 'wa', 'ヲ': 'wo', 'ン': 'n',
    'ガ': 'ga', 'ギ': 'gi', 'グ': 'gu', 'ゲ': 'ge', 'ゴ': 'go',
    'ザ': 'za', 'ジ': 'ji', 'ズ': 'zu', 'ゼ': 'ze', 'ゾ': 'zo',
    'ダ': 'da', 'ヂ': 'ji', 'ヅ': 'zu', 'デ': 'de', 'ド': 'do',
    'バ': 'ba', 'ビ': 'bi', 'ブ': 'bu', 'ベ': 'be', 'ボ': 'bo',
    'パ': 'pa', 'ピ': 'pi', 'プ': 'pu', 'ペ': 'pe', 'ポ': 'po',
    'キャ': 'kya', 'キュ': 'kyu', 'キョ': 'kyo',
    'シャ': 'sha', 'シュ': 'shu', 'ショ': 'sho',
    'チャ': 'cha', 'チュ': 'chu', 'チョ': 'cho',
  };

  // Cyrillic table
  static const Map<String, String> _cyrillicMap = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo',
    'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
    'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
    'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
    'ъ': '', 'ы': 'y', 'ь': "'", 'э': 'e', 'ю': 'yu', 'я': 'ya',
    'А': 'A', 'Б': 'B', 'В': 'V', 'Г': 'G', 'Д': 'D', 'Е': 'E', 'Ё': 'Yo',
    'Ж': 'Zh', 'З': 'Z', 'И': 'I', 'Й': 'Y', 'К': 'K', 'Л': 'L', 'М': 'M',
    'Н': 'N', 'О': 'O', 'П': 'P', 'Р': 'R', 'С': 'S', 'Т': 'T', 'У': 'U',
    'Ф': 'F', 'Х': 'Kh', 'Ц': 'Ts', 'Ч': 'Ch', 'Ш': 'Sh', 'Щ': 'Shch',
    'Ъ': '', 'Ы': 'Y', 'Ь': "'", 'Э': 'E', 'Ю': 'Yu', 'Я': 'Ya',
  };

  // Hindi Devanagari tables
  static const Map<int, String> _hindiVowels = {
    0x0905: 'a', 0x0906: 'aa', 0x0907: 'i', 0x0908: 'ee', 0x0909: 'u',
    0x090A: 'oo', 0x090B: 'ri', 0x090F: 'e', 0x0910: 'ai', 0x0913: 'o', 0x0914: 'au',
  };

  static const Map<int, String> _hindiConsonants = {
    0x0915: 'k', 0x0916: 'kh', 0x0917: 'g', 0x0918: 'gh', 0x0919: 'ng',
    0x091A: 'ch', 0x091B: 'chh', 0x091C: 'j', 0x091D: 'jh', 0x091E: 'ny',
    0x091F: 't', 0x0920: 'th', 0x0921: 'd', 0x0922: 'dh', 0x0923: 'n',
    0x0924: 't', 0x0925: 'th', 0x0926: 'd', 0x0927: 'dh', 0x0928: 'n',
    0x092A: 'p', 0x092B: 'ph', 0x092C: 'b', 0x092D: 'bh', 0x092E: 'm',
    0x092F: 'y', 0x0930: 'r', 0x0932: 'l', 0x0933: 'l', 0x0935: 'v',
    0x0936: 'sh', 0x0937: 'sh', 0x0938: 's', 0x0939: 'h',
  };

  static const Map<int, String> _hindiMatras = {
    0x093E: 'aa', 0x093F: 'i', 0x0940: 'ee', 0x0941: 'u', 0x0942: 'oo',
    0x0943: 'ri', 0x0947: 'e', 0x0948: 'ai', 0x094B: 'o', 0x094C: 'au',
  };

  // Common Chinese characters to Pinyin (Offline Pinyin Engine)
  static const Map<String, String> _cjkPinyin = {
    '你': 'ni', '我': 'wo', '他': 'ta', '她': 'ta', '它': 'ta', '们': 'men',
    '的': 'de', '是': 'shi', '在': 'zai', '有': 'you', '个': 'ge', '不': 'bu',
    '了': 'le', '人': 'ren', '这': 'zhe', '中': 'zhong', '大': 'da', '来': 'lai',
    '上': 'shang', '国': 'guo', '到': 'dao', '说': 'shuo', '要': 'yao', '去': 'qu',
    '子': 'zi', '得': 'de', '也': 'ye', '和': 'he', '下': 'xia', '过': 'guo',
    '天': 'tian', '地': 'di', '心': 'xin', '生': 'sheng', '爱': 'ai', '情': 'qing',
    '好': 'hao', '看': 'kan', '听': 'ting', '想': 'xiang', '知': 'zhi', '道': 'dao',
    '能': 'neng', '会': 'hui', '就': 'jiu', '着': 'zhe', '没': 'mei', '自': 'zi',
    '己': 'ji', '年': 'nian', '后': 'hou', '前': 'qian', '家': 'jia', '多': 'duo',
    '少': 'shao', '长': 'chang', '小': 'xiao', '风': 'feng', '雨': 'yu', '夜': 'ye',
    '光': 'guang', '星': 'xing', '月': 'yue', '海': 'hai', '花': 'hua', '歌': 'ge',
    '声': 'sheng', '梦': 'meng', '泪': 'lei', '痛': 'tong', '伤': 'shang', '忘': 'wang',
    '别': 'bie', '走': 'zou', '等': 'deng', '谁': 'shui', '快': 'kuai', '乐': 'le',
    '美': 'mei', '真': 'zhen', '给': 'gei', '把': 'ba', '一': 'yi', '二': 'er',
    '三': 'san', '四': 'si', '五': 'wu', '六': 'liu', '七': 'qi', '八': 'ba',
    '九': 'jiu', '十': 'shi', '百': 'bai', '千': 'qian', '万': 'wan', '零': 'ling',
    '只': 'zhi', '见': 'jian', '闻': 'wen', '感': 'gan', '觉': 'jue', '喜': 'xi',
    '欢': 'huan', '恋': 'lian', '念': 'nian', '思': 'si', '忆': 'yi', '苦': 'ku',
    '难': 'nan', '易': 'yi', '简': 'jian', '单': 'dan', '纯': 'chun', '洁': 'jie',
    '白': 'bai', '黑': 'hei', '红': 'hong', '蓝': 'lan', '绿': 'lv', '黄': 'huang',
    '紫': 'zi', '春': 'chun', '夏': 'xia', '秋': 'qiu', '冬': 'dong', '晨': 'chen',
    '晴': 'qing', '阴': 'yin', '阳': 'yang', '云': 'yun', '雾': 'wu', '雪': 'xue',
    '霜': 'shuang', '冰': 'bing', '树': 'shu', '木': 'mu', '林': 'lin', '草': 'cao',
    '叶': 'ye', '鸟': 'niao', '鱼': 'yu', '飞': 'fei', '游': 'you', '跑': 'pao',
    '步': 'bu', '停': 'ting', '留': 'liu', '住': 'zhu', '所': 'suo', '处': 'chu',
    '方': 'fang', '向': 'xiang', '远': 'yuan', '近': 'jin', '深': 'shen', '浅': 'qian',
    '高': 'gao', '低': 'di', '重': 'zhong', '轻': 'qing', '强': 'qiang', '弱': 'ruo',
    '冷': 'leng', '热': 're', '暖': 'nuan', '温': 'wen', '凉': 'liang', '甜': 'tian',
    '酸': 'suan', '辣': 'la', '咸': 'xian', '醉': 'zui', '醒': 'xing', '睡': 'shui',
    '眼': 'yan', '眸': 'mou', '眉': 'mei', '唇': 'chun', '口': 'kou', '耳': 'er',
    '面': 'mian', '头': 'tou', '发': 'fa', '身': 'shen', '手': 'shou', '指': 'zhi',
    '足': 'zu', '脚': 'jiao', '影': 'ying', '魂': 'hun', '魄': 'po', '神': 'shen',
    '仙': 'xian', '鬼': 'gui', '怪': 'guai', '灵': 'ling', '命': 'ming', '运': 'yun',
    '缘': 'yuan', '份': 'fen', '安': 'an', '平': 'ping', '宁': 'ning', '静': 'jing',
    '默': 'mo', '寂': 'ji', '寞': 'mo', '孤': 'gu', '独': 'du', '伴': 'ban',
    '友': 'you', '朋': 'peng', '亲': 'qin', '恨': 'hen', '怨': 'yuan', '明': 'ming',
    '智': 'zhi', '慧': 'hui', '世': 'shi', '界': 'jie', '空': 'kong', '间': 'jian',
    '岁': 'sui', '轮': 'lun', '回': 'hui', '诺': 'nuo', '约': 'yue', '定': 'ding',
    '期': 'qi', '待': 'dai', '盼': 'pan', '望': 'wang', '渴': 'ke', '愿': 'yuan',
    '祈': 'qi', '祷': 'dao', '祝': 'zhu', '福': 'fu', '护': 'hu', '守': 'shou',
    '拥': 'yong', '抱': 'bao', '吻': 'wen', '触': 'chu', '摸': 'mo', '牵': 'qian',
    '引': 'yin', '迷': 'mi', '茫': 'mang', '懂': 'dong', '解': 'jie', '诉': 'su',
    '呼': 'hu', '唤': 'huan', '喊': 'han', '叫': 'jiao', '哭': 'ku', '笑': 'xiao',
    '叹': 'tan', '唱': 'chang', '弹': 'tan', '奏': 'zou', '舞': 'wu', '转': 'zhuan',
    '跳': 'tiao', '渡': 'du', '岸': 'an', '港': 'gang', '潮': 'chao', '浪': 'lang',
    '归': 'gui', '路': 'lu', '边': 'bian', '尽': 'jin', '绝': 'jue', '净': 'jing',
    '透': 'tou', '亮': 'liang', '细': 'xi', '柔': 'rou', '坚': 'jian', '勇': 'yong',
    '燃': 'ran', '烧': 'shao', '落': 'luo', '坠': 'zhui', '失': 'shi', '找': 'zhao',
    '再': 'zai', '分': 'fen', '离': 'li', '相': 'xiang', '遇': 'yu', '逢': 'feng',
    '陪': 'pei', '同': 'tong', '共': 'gong', '度': 'du', '每': 'mei', '刻': 'ke',
    '秒': 'miao', '钟': 'zhong', '点': 'dian', '时': 'shi', '此': 'ci', '彼': 'bi',
    '哪': 'na', '里': 'li', '外': 'wai', '内': 'nei', '旁': 'pang', '侧': 'ce',
    '开': 'kai', '关': 'guan', '闭': 'bi', '启': 'qi', '动': 'dong', '止': 'zhi',
    '始': 'shi', '终': 'zhong', '结': 'jie', '束': 'shu', '尾': 'wei', '初': 'chu',
    '末': 'mo', '永': 'yong', '恒': 'heng', '久': 'jiu', '瞬': 'shun',
    '息': 'xi', '忽': 'hu', '然': 'ran', '突': 'tu', '渐': 'jian', '慢': 'man',
    '急': 'ji', '慌': 'huang', '忙': 'mang', '闲': 'xian', '喧': 'xuan', '嚣': 'xiao',
    '闹': 'nao', '吵': 'chao', '暗': 'an', '灰': 'hui', '彩': 'cai', '绚': 'xuan',
    '烂': 'lan', '华': 'hua', '丽': 'li', '朴': 'pu', '素': 'su', '淡': 'dan',
    '浓': 'nong', '烈': 'lie', '微': 'wei', '沉': 'chen', '浮': 'fu', '叠': 'die',
    '交': 'jiao', '织': 'zhi', '缠': 'chan', '绕': 'rao', '锁': 'suo', '链': 'lian',
    '碎': 'sui', '裂': 'lie', '破': 'po', '损': 'sun', '完': 'wan', '整': 'zheng',
    '缺': 'que', '残': 'can', '满': 'man', '盈': 'ying', '虚': 'xu', '实': 'shi',
    '存': 'cun', '逝': 'shi', '追': 'zhui', '逐': 'zhu', '逃': 'tao', '避': 'bi',
    '躲': 'duo', '藏': 'cang', '露': 'lu', '现': 'xian', '隐': 'yin', '匿': 'ni',
    '显': 'xian', '示': 'shi', '表': 'biao', '达': 'da', '传': 'chuan', '递': 'di',
    '送': 'song', '迎': 'ying', '接': 'jie', '受': 'shou', '承': 'cheng', '担': 'dan',
    '负': 'fu', '载': 'zai', '卸': 'xie', '放': 'fang', '松': 'song', '紧': 'jin',
    '张': 'zhang', '弛': 'chi', '缓': 'huan', '悠': 'you', '扬': 'yang', '飘': 'piao',
    '升': 'sheng', '降': 'jiang', '起': 'qi', '伏': 'fu', '跌': 'die', '宕': 'dang',
    '坎': 'kan', '坷': 'ke', '坦': 'tan', '顺': 'shun', '畅': 'chang', '阻': 'zu',
    '碍': 'ai', '跨': 'kua', '越': 'yue', '攀': 'pan', '登': 'deng', '涉': 'she',
    '踏': 'ta', '行': 'xing', '旅': 'lv', '客': 'ke', '主': 'zhu', '宾': 'bin',
    '席': 'xi', '座': 'zuo', '位': 'wei', '置': 'zhi', '局': 'ju', '形': 'xing',
    '态': 'tai', '样': 'yang', '式': 'shi', '种': 'zhong', '类': 'lei', '致': 'zhi',
    '雅': 'ya', '俗': 'su', '清': 'qing', '浊': 'zhuo', '杂': 'za', '质': 'zhi',
    '本': 'ben', '源': 'yuan', '根': 'gen', '基': 'ji', '极': 'ji',
    '寻': 'xun', '觅': 'mi', '成': 'cheng', '败': 'bai', '胜': 'sheng', '输': 'shu',
    '赢': 'ying', '争': 'zheng', '夺': 'duo', '抢': 'qiang', '让': 'rang', '予': 'yu',
    '取': 'qu', '求': 'qiu', '索': 'suo', '探': 'tan', '究': 'jiu', '查': 'cha',
    '验': 'yan', '证': 'zheng', '悟': 'wu', '晓': 'xiao', '悉': 'xi', '已': 'yi',
    '曾': 'ceng', '经': 'jing', '将': 'jiang', '即': 'ji', '正': 'zheng', '当': 'dang',
    '适': 'shi', '宜': 'yi', '恰': 'qia', '偶': 'ou', '必': 'bi',
    '对': 'dui', '互': 'hu', '各': 'ge', '双': 'shuang', '两': 'liang', '几': 'ji',
    '许': 'xu', '甚': 'shen', '至': 'zhi', '且': 'qie', '虽': 'sui', '但': 'dan',
    '却': 'que', '而': 'er', '因': 'yin', '为': 'wei', '以': 'yi', '故': 'gu',
    '由': 'you', '从': 'cong', '朝': 'chao', '背': 'bei', '随': 'sui', '依': 'yi',
    '凭': 'ping', '借': 'jie', '赖': 'lai', '托': 'tuo', '付': 'fu', '寄': 'ji',
    '惜': 'xi', '怜': 'lian', '哀': 'ai', '悲': 'bei', '愁': 'chou',
    '恼': 'nao', '烦': 'fan', '躁': 'zao', '怒': 'nu', '悦': 'yue', '欣': 'xin',
    '愉': 'yu', '爽': 'shuang', '朗': 'lang', '豪': 'hao', '纵': 'zong', '逸': 'yi',
    '洒': 'sa', '脱': 'tuo', '野': 'ye', '山': 'shan',
    '川': 'chuan', '湖': 'hu', '江': 'jiang', '溪': 'xi', '流': 'liu', '泉': 'quan',
    '潭': 'tan', '池': 'chi', '洋': 'yang', '岛': 'dao', '石': 'shi', '岩': 'yan',
    '峰': 'feng', '岭': 'ling', '原': 'yuan', '谷': 'gu', '崖': 'ya', '洞': 'dong',
  };

  // Common Japanese Kanji compounds & characters for offline Romaji fallback
  static const Map<String, String> _commonKanjiMap = {
    // Multi-character compounds
    '不埒': 'furachi',
    '不安定': 'fuantei',
    '文字': 'moji',
    '踊り出す': 'odoridasu',
    '踊り': 'odori',
    '音楽': 'ongaku',
    '今日': 'kyou',
    '明日': 'ashita',
    '昨日': 'kinou',
    '時間': 'jikan',
    '世界': 'sekai',
    '友達': 'tomodachi',
    '綺麗': 'kirei',
    '本当': 'hontou',
    '大丈夫': 'daijoubu',
    'ありがとう': 'arigatou',
    'さようなら': 'sayounara',
    // Single high-frequency kanji
    '駅': 'eki',
    '音': 'oto',
    '鳴': 'na',
    '刻': 'kizan',
    '人': 'hito',
    '空': 'sora',
    '心': 'kokoro',
    '愛': 'ai',
    '恋': 'koi',
    '夢': 'yume',
    '夜': 'yoru',
    '朝': 'asa',
    '昼': 'hiru',
    '光': 'hikari',
    '影': 'kage',
    '星': 'hoshi',
    '月': 'tsuki',
    '日': 'hi',
    '花': 'hana',
    '雨': 'ame',
    '風': 'kaze',
    '海': 'umi',
    '山': 'yama',
    '川': 'kawa',
    '道': 'michi',
    '街': 'machi',
    '声': 'koe',
    '歌': 'uta',
    '手': 'te',
    '目': 'me',
    '足': 'ashi',
    '今': 'ima',
    '何': 'nani',
    '誰': 'dare',
    '私': 'watashi',
    '僕': 'boku',
    '君': 'kimi',
    '見': 'mi',
    '聞': 'ki',
    '言': 'i',
    '話': 'hana',
    '思': 'omo',
    '知': 'shi',
    '行': 'i',
    '来': 'ku',
    '帰': 'kae',
    '出': 'de',
    '入': 'hai',
    '立': 'ta',
    '座': 'suwa',
    '歩': 'aru',
    '走': 'hashi',
    '待': 'ma',
    '止': 'to',
    '涙': 'namida',
    '痛': 'ita',
    '笑': 'wara',
    '泣': 'na',
    '生': 'i',
    '死': 'shi',
    '色': 'iro',
    '赤': 'aka',
    '青': 'ao',
    '白': 'shiro',
    '黒': 'kuro',
    '春': 'haru',
    '夏': 'natsu',
    '秋': 'aki',
    '冬': 'fuyu',
    '神': 'kami',
    '天': 'ten',
    '地': 'chi',
  };

  static bool hasForeign(
    String text, {
    bool japanese = true,
    bool korean = true,
    bool chinese = true,
    bool hindi = true,
  }) {
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      // Hangul (0xAC00 - 0xD7AF) or Jamo (0x1100 - 0x11FF)
      if (korean && ((code >= 0xAC00 && code <= 0xD7AF) || (code >= 0x1100 && code <= 0x11FF))) return true;
      // Hiragana (0x3040 - 0x309F) & Katakana (0x30A0 - 0x30FF)
      if (japanese && (code >= 0x3040 && code <= 0x30FF)) return true;
      // Hindi Devanagari (0x0900 - 0x097F)
      if (hindi && (code >= 0x0900 && code <= 0x097F)) return true;
      // Cyrillic (0x0400 - 0x04FF)
      if (code >= 0x0400 && code <= 0x04FF) return true;
      // CJK Ideographs (0x4E00 - 0x9FFF) - shared by Japanese and Chinese
      if ((japanese || chinese) && (code >= 0x4E00 && code <= 0x9FFF)) return true;
    }
    return false;
  }

  static String romanize(
    String text, {
    bool japanese = true,
    bool korean = true,
    bool chinese = true,
    bool hindi = true,
  }) {
    if (!hasForeign(text, japanese: japanese, korean: korean, chinese: chinese, hindi: hindi)) {
      return text;
    }
    final sb = StringBuffer();
    final hasKana = RegExp(r'[\u3040-\u30FF]').hasMatch(text);
    int i = 0;
    while (i < text.length) {
      final code = text.codeUnitAt(i);

      // 0. Japanese Kanji multi-character compounds (offline fallback - only when text contains Kana or not Chinese)
      if (japanese && (hasKana || !chinese)) {
        bool matchedCompound = false;
        for (int len = 4; len >= 2; len--) {
          if (i + len <= text.length) {
            final sub = text.substring(i, i + len);
            if (_commonKanjiMap.containsKey(sub)) {
              if (sb.isNotEmpty && !sb.toString().endsWith(' ')) {
                sb.write(' ');
              }
              sb.write(_commonKanjiMap[sub]);
              i += len;
              matchedCompound = true;
              break;
            }
          }
        }
        if (matchedCompound) continue;
      }

      // 1. Japanese 2-character Kana combinations (e.g. しゃ, キャ)
      if (japanese && i + 1 < text.length) {
        final pair = text.substring(i, i + 2);
        if (_kanaMap.containsKey(pair)) {
          sb.write(_kanaMap[pair]);
          i += 2;
          continue;
        }
      }

      // 2. Japanese small tsu (っ or ッ) for consonant doubling
      if (japanese && (text[i] == 'っ' || text[i] == 'ッ')) {
        if (i + 1 < text.length) {
          final nextChar = text[i + 1];
          final nextRomaji = _kanaMap[nextChar];
          if (nextRomaji != null && nextRomaji.isNotEmpty) {
            sb.write(nextRomaji[0]);
            i++;
            continue;
          }
        }
      }

      // 3. Single Kana
      final singleChar = text[i];
      if (japanese && _kanaMap.containsKey(singleChar)) {
        sb.write(_kanaMap[singleChar]);
        i++;
        continue;
      }

      // 3.5 Japanese single Kanji (offline fallback - only if has Kana or not Chinese)
      if (japanese && (hasKana || !chinese) && _commonKanjiMap.containsKey(singleChar)) {
        if (sb.isNotEmpty && !sb.toString().endsWith(' ')) {
          sb.write(' ');
        }
        sb.write(_commonKanjiMap[singleChar]);
        i++;
        continue;
      }

      // 4. Cyrillic
      if (_cyrillicMap.containsKey(singleChar)) {
        sb.write(_cyrillicMap[singleChar]);
        i++;
        continue;
      }

      // 5. Korean Hangul syllable
      if (korean && code >= 0xAC00 && code <= 0xD7AF) {
        final syllableIndex = code - 0xAC00;
        final initialIndex = syllableIndex ~/ 588;
        final vowelIndex = (syllableIndex % 588) ~/ 28;
        final finalIndex = syllableIndex % 28;

        sb.write(_koreanInitials[initialIndex]);
        sb.write(_koreanVowels[vowelIndex]);
        sb.write(_koreanFinals[finalIndex]);
        i++;
        continue;
      }

      // 5.1 Korean standalone compatibility Jamo
      if (korean && _koreanJamo.containsKey(code)) {
        sb.write(_koreanJamo[code]);
        i++;
        continue;
      }

      // 6. Hindi Devanagari
      if (hindi && code >= 0x0900 && code <= 0x097F) {
        // Independent Vowel
        if (_hindiVowels.containsKey(code)) {
          sb.write(_hindiVowels[code]);
          i++;
          continue;
        }

        // Consonant
        if (_hindiConsonants.containsKey(code)) {
          String cons = _hindiConsonants[code]!;
          i++;

          // Check Nukta (़)
          if (i < text.length && text.codeUnitAt(i) == 0x093C) {
            if (code == 0x0915) {
              cons = 'q';
            } else if (code == 0x091C) {
              cons = 'z';
            } else if (code == 0x092B) {
              cons = 'f';
            } else if (code == 0x0921) {
              cons = 'r';
            } else if (code == 0x0922) {
              cons = 'rh';
            }
            i++;
          }

          sb.write(cons);

          // Check Virama / Halant (्)
          if (i < text.length && text.codeUnitAt(i) == 0x094D) {
            // Suppress inherent 'a'
            i++;
            continue;
          }

          // Check Matra (vowel sign)
          if (i < text.length && _hindiMatras.containsKey(text.codeUnitAt(i))) {
            sb.write(_hindiMatras[text.codeUnitAt(i)]);
            i++;
            continue;
          }

          // Check Anusvara / Chandrabindu
          if (i < text.length && (text.codeUnitAt(i) == 0x0901 || text.codeUnitAt(i) == 0x0902)) {
            sb.write('an');
            i++;
            continue;
          }

          // Inherent 'a' handling:
          // Modern Hindi schwa deletion: don't append 'a' at end of word or end of line
          final isEndOfWord = (i >= text.length) ||
              text[i] == ' ' ||
              text[i] == '\n' ||
              RegExp(r'[^\u0900-\u097F]').hasMatch(text[i]);
          if (!isEndOfWord) {
            sb.write('a');
          }
          continue;
        }

        // Standalone Matra or Anusvara
        if (_hindiMatras.containsKey(code)) {
          sb.write(_hindiMatras[code]);
          i++;
          continue;
        }
        if (code == 0x0901 || code == 0x0902) {
          sb.write('n');
          i++;
          continue;
        }
        if (code == 0x0903) {
          sb.write('h');
          i++;
          continue;
        }
        i++;
        continue;
      }

      // 7. Chinese Pinyin lookup
      if (chinese && _cjkPinyin.containsKey(singleChar)) {
        if (sb.isNotEmpty && !sb.toString().endsWith(' ')) {
          sb.write(' ');
        }
        sb.write(_cjkPinyin[singleChar]);
        i++;
        continue;
      }

      // Katakana prolonged sound mark ー
      if (japanese && singleChar == 'ー') {
        if (sb.isNotEmpty) {
          final last = sb.toString()[sb.length - 1];
          sb.write(last);
        }
        i++;
        continue;
      }

      // Default
      sb.write(singleChar);
      i++;
    }
    return sb.toString().trim();
  }

  static final Map<String, TransliterationResult> _transliterationCache = {};

  /// Performs accurate online transliteration (Kanji compounds, Kana, Hanzi, Hangul)
  /// and English translation via Google's transliteration API. Falls back to offline romanizer.
  static Future<TransliterationResult> transliterateOnline(
    String text, {
    bool japanese = true,
    bool korean = true,
    bool chinese = true,
    bool hindi = true,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const TransliterationResult();
    }
    final cached = _transliterationCache[trimmed];
    if (cached != null) return cached;

    try {
      final uri = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=rm&dt=t&q=${Uri.encodeComponent(trimmed)}',
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        String? romaji;
        String? translation;
        if (decoded is List && decoded.isNotEmpty) {
          final topList = decoded[0] as List?;
          if (topList != null) {
            final transParts = <String>[];
            for (final item in topList) {
              if (item is List && item.isNotEmpty && item[0] != null) {
                final s = item[0].toString().trim();
                if (s.isNotEmpty) transParts.add(s);
              } else if (item is List && item.length > 3 && item[3] != null) {
                final r = item[3].toString().trim();
                if (r.isNotEmpty) romaji = r;
              }
            }
            if (transParts.isNotEmpty) {
              final joined = transParts.join(' ').trim();
              if (joined.toLowerCase() != trimmed.toLowerCase()) {
                translation = joined;
              }
            }
          }
        }

        if (romaji == null || romaji.isEmpty || romaji.toLowerCase() == trimmed.toLowerCase()) {
          if (hasForeign(trimmed, japanese: japanese, korean: korean, chinese: chinese, hindi: hindi)) {
            romaji = romanize(trimmed, japanese: japanese, korean: korean, chinese: chinese, hindi: hindi);
          }
        }

        final res = TransliterationResult(romanized: romaji, translation: translation);
        _transliterationCache[trimmed] = res;
        return res;
      }
    } catch (e) {
      debugPrint('LyricsRomanizer online error: $e');
    }

    final offlineRomaji = hasForeign(trimmed, japanese: japanese, korean: korean, chinese: chinese, hindi: hindi)
        ? romanize(trimmed, japanese: japanese, korean: korean, chinese: chinese, hindi: hindi)
        : null;
    final res = TransliterationResult(romanized: offlineRomaji);
    _transliterationCache[trimmed] = res;
    return res;
  }

  /// Batch transliterates lines efficiently with newline chunking to avoid 429 rate-limiting.
  static Future<Map<String, TransliterationResult>> batchTransliterate(
    List<String> texts, {
    bool japanese = true,
    bool korean = true,
    bool chinese = true,
    bool hindi = true,
  }) async {
    final uniqueTexts = texts
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && hasForeign(t, japanese: japanese, korean: korean, chinese: chinese, hindi: hindi))
        .toSet()
        .toList();
    final results = <String, TransliterationResult>{};
    if (uniqueTexts.isEmpty) return results;

    // Check cache first
    final uncached = <String>[];
    for (final text in uniqueTexts) {
      if (_transliterationCache.containsKey(text)) {
        results[text] = _transliterationCache[text]!;
      } else {
        uncached.add(text);
      }
    }

    if (uncached.isNotEmpty) {
      const chunkSize = 20;
      for (int i = 0; i < uncached.length; i += chunkSize) {
        final chunk = uncached.sublist(
          i,
          (i + chunkSize > uncached.length) ? uncached.length : i + chunkSize,
        );
        final joinedText = chunk.join('\n');
        try {
          final uri = Uri.parse(
            'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=rm&dt=t&q=${Uri.encodeComponent(joinedText)}',
          );
          final response = await http.get(
            uri,
            headers: {'User-Agent': 'Mozilla/5.0'},
          ).timeout(const Duration(seconds: 4));

          if (response.statusCode == 200) {
            final decoded = jsonDecode(response.body);
            String? fullRomaji;
            final fullTranslations = <String>[];
            if (decoded is List && decoded.isNotEmpty) {
              final topList = decoded[0] as List?;
              if (topList != null) {
                for (final item in topList) {
                  if (item is List && item.isNotEmpty && item[0] != null) {
                    final s = item[0].toString();
                    if (s.isNotEmpty) fullTranslations.add(s);
                  } else if (item is List && item.length > 3 && item[3] != null) {
                    final r = item[3].toString();
                    if (r.isNotEmpty) fullRomaji = r;
                  }
                }
              }
            }

            final romajiLines = fullRomaji?.split('\n') ?? [];
            final transLines = fullTranslations.join('').split('\n');

            for (int j = 0; j < chunk.length; j++) {
              final itemText = chunk[j];
              String? itemRomaji = (j < romajiLines.length) ? romajiLines[j].trim() : null;
              String? itemTrans = (j < transLines.length) ? transLines[j].trim() : null;

              if (itemRomaji == null || itemRomaji.isEmpty || itemRomaji.toLowerCase() == itemText.toLowerCase()) {
                itemRomaji = romanize(itemText, japanese: japanese, korean: korean, chinese: chinese, hindi: hindi);
              }
              if (itemTrans != null && (itemTrans.isEmpty || itemTrans.toLowerCase() == itemText.toLowerCase())) {
                itemTrans = null;
              }

              final res = TransliterationResult(romanized: itemRomaji, translation: itemTrans);
              results[itemText] = res;
              _transliterationCache[itemText] = res;
            }
          } else {
            throw Exception('HTTP ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('LyricsRomanizer batch online error: $e');
          for (final itemText in chunk) {
            final offline = romanize(itemText, japanese: japanese, korean: korean, chinese: chinese, hindi: hindi);
            final res = TransliterationResult(romanized: offline);
            results[itemText] = res;
            _transliterationCache[itemText] = res;
          }
        }
      }
    }

    return results;
  }
}

/// Result of transliteration and optional translation.
class TransliterationResult {
  final String? romanized;
  final String? translation;

  const TransliterationResult({this.romanized, this.translation});
}

/// Service that fetches synchronized lyrics from LRCLIB, KuGou, and YouTube subtitles.
class LyricsService {
  LyricsService._();
  static final LyricsService instance = LyricsService._();

  final Map<String, LyricsData> _cache = {};
  final YoutubeExplode _ytExplode = YoutubeExplode();

  static final RegExp _soundTagRegex = RegExp(
    r'(\[(?:music|applause|cheering|laughter|chuckles|gasp|sigh|groan|screaming|singing|instrumental|intro|outro|solo|ongaku|hakushu|音楽|拍手|歓声|笑い)\])|[♪♫♬]',
    caseSensitive: false,
  );

  /// Strips sound effect tags like [Music], [音楽], [拍手], and musical symbols.
  static String sanitizeLyricText(String text) {
    return text.replaceAll(_soundTagRegex, '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Pre-populates lyrics in cache for testing.
  void setLyricsForTesting(String key, LyricsData data) {
    _cache[key] = data;
  }

  /// Fetches synchronized lyrics for the given [track].
  Future<LyricsData?> fetchLyrics(
    Track track, {
    SettingsService? settingsService,
    bool forceRefresh = false,
  }) async {
    final cacheKey = track.id.isNotEmpty ? track.id : '${track.title}_${track.author}';
    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }
    if (forceRefresh) {
      _cache.remove(cacheKey);
    }

    final preferred = settingsService?.preferredLyricsProvider.toLowerCase() ?? 'betterlyrics';
    final lrclibEnabled = settingsService?.enableLrcLib ?? true;
    final kugouEnabled = settingsService?.enableKuGou ?? true;
    final neteaseEnabled = settingsService?.enableNetEase ?? true;
    final simpMusicEnabled = settingsService?.enableSimpMusic ?? true;
    final betterLyricsEnabled = settingsService?.enableBetterLyrics ?? true;

    final variants = <String, LyricsData>{};

    // Run preferred and alternate providers concurrently for ultra-fast response
    final futures = <Future<void>>[];

    if (lrclibEnabled) {
      futures.add(() async {
        try {
          final data = await _fetchFromLrclib(track, settings: settingsService);
          if (data != null && data.isNotEmpty) {
            variants['LRCLIB'] = data;
          }
        } catch (e) {
          debugPrint('LyricsService: LRCLIB error: $e');
        }
      }());
    }

    if (kugouEnabled) {
      futures.add(() async {
        try {
          final data = await _fetchFromKuGou(track, settings: settingsService);
          if (data != null && data.isNotEmpty) {
            variants['KuGou'] = data;
          }
        } catch (e) {
          debugPrint('LyricsService: KuGou error: $e');
        }
      }());
    }

    if (neteaseEnabled) {
      futures.add(() async {
        try {
          final data = await _fetchFromNetEase(track, settings: settingsService);
          if (data != null && data.isNotEmpty) {
            variants['NetEase'] = data;
          }
        } catch (e) {
          debugPrint('LyricsService: NetEase error: $e');
        }
      }());
    }

    if (simpMusicEnabled || betterLyricsEnabled) {
      futures.add(() async {
        try {
          final data = await _fetchFromSimpMusic(track, settings: settingsService);
          if (data != null && data.isNotEmpty) {
            variants[data.source ?? 'SimpMusic'] = data;
          }
        } catch (e) {
          debugPrint('LyricsService: SimpMusic error: $e');
        }
      }());
    }

    await Future.wait(futures);

    // If neither returned lyrics, try YouTube closed captions (official/clean only)
    if (variants.isEmpty && track.id.isNotEmpty && !track.id.startsWith('spotify:')) {
      try {
        final ytCaptions = await _fetchFromYouTubeCaptions(track.id, settings: settingsService);
        if (ytCaptions != null && ytCaptions.isNotEmpty) {
          variants[ytCaptions.source ?? 'YouTube Subtitles'] = ytCaptions;
        }
      } catch (e) {
        debugPrint('LyricsService: YouTube captions error: $e');
      }
    }

    if (variants.isEmpty) return null;

    // Pick primary provider based on user preference or best synced source
    LyricsData primary;
    if (preferred.contains('netease') && variants.containsKey('NetEase')) {
      primary = variants['NetEase']!;
    } else if (preferred.contains('simp') && variants.containsKey('SimpMusic')) {
      primary = variants['SimpMusic']!;
    } else if (preferred.contains('better') && variants.containsKey('BetterLyrics')) {
      primary = variants['BetterLyrics']!;
    } else if (preferred.contains('better') && variants.containsKey('SimpMusic')) {
      primary = variants['SimpMusic']!;
    } else if (preferred.contains('kugou') && variants.containsKey('KuGou')) {
      primary = variants['KuGou']!;
    } else if (preferred.contains('lrclib') && variants.containsKey('LRCLIB')) {
      primary = variants['LRCLIB']!;
    } else {
      primary = variants.values.firstWhere(
        (v) => v.isSynced,
        orElse: () => variants.values.first,
      );
    }

    final autoAlign = settingsService?.autoAlignLyricsOffset ?? true;
    final autoSync = settingsService?.autoSyncPlainLyrics ?? true;

    // 1. If lyrics are plain/unsynced, auto-sync them using YouTube caption speech markers
    if (!primary.isSynced && autoSync && track.id.isNotEmpty && !track.id.startsWith('spotify:')) {
      try {
        final syncedFromCaptions = await _autoSyncPlainLyricsWithCaptions(track.id, primary, settings: settingsService);
        if (syncedFromCaptions != null && syncedFromCaptions.lines.isNotEmpty) {
          primary = syncedFromCaptions;
          variants[syncedFromCaptions.source ?? 'Auto-Synced'] = syncedFromCaptions;
        }
      } catch (e) {
        debugPrint('LyricsService: autoSyncPlainLyrics error: $e');
      }
    }

    // 2. If lyrics are synced, auto-calibrate timing offset (intro/delay correction)
    if (primary.isSynced && autoAlign && track.id.isNotEmpty && !track.id.startsWith('spotify:')) {
      final manualOffset = settingsService?.getLyricsOffsetMs(track.id) ?? 0;
      if (manualOffset == 0) {
        try {
          final aligned = await _autoAlignLyricsTiming(track.id, primary);
          if (aligned != null) {
            primary = aligned;
            variants[aligned.source ?? primary.source ?? 'Auto-Aligned'] = aligned;
          }
        } catch (e) {
          debugPrint('LyricsService: autoAlignLyricsTiming error: $e');
        }
      }
    }

    final result = primary.copyWith(providerVariants: variants);
    _cache[cacheKey] = result;
    return result;
  }

  /// Switches lyrics directly to a specified provider if available.
  Future<LyricsData?> fetchLyricsWithProvider(
    Track track,
    String providerName, {
    SettingsService? settingsService,
  }) async {
    final cacheKey = track.id.isNotEmpty ? track.id : '${track.title}_${track.author}';
    final cached = _cache[cacheKey];
    if (cached != null && cached.providerVariants.containsKey(providerName)) {
      final chosen = cached.providerVariants[providerName]!;
      final updated = chosen.copyWith(providerVariants: cached.providerVariants);
      _cache[cacheKey] = updated;
      return updated;
    }

    // Direct on-demand provider fetch
    LyricsData? fresh;
    if (providerName.toLowerCase().contains('netease') || providerName.toLowerCase().contains('163')) {
      fresh = await _fetchFromNetEase(track, settings: settingsService);
    } else if (providerName.toLowerCase().contains('simp') || providerName.toLowerCase().contains('betterlyrics')) {
      fresh = await _fetchFromSimpMusic(track, settings: settingsService);
    } else if (providerName.toLowerCase().contains('kugou')) {
      fresh = await _fetchFromKuGou(track, settings: settingsService);
    } else if (providerName.toLowerCase().contains('lrclib')) {
      fresh = await _fetchFromLrclib(track, settings: settingsService);
    } else if (providerName.toLowerCase().contains('youtube')) {
      fresh = await _fetchFromYouTubeCaptions(track.id, settings: settingsService);
    }

    if (fresh != null && fresh.isNotEmpty) {
      final variants = Map<String, LyricsData>.from(cached?.providerVariants ?? {});
      variants[providerName] = fresh;
      final updated = fresh.copyWith(providerVariants: variants);
      _cache[cacheKey] = updated;
      return updated;
    }

    return null;
  }

  Future<LyricsData?> _fetchFromLrclib(Track track, {SettingsService? settings}) async {
    final cleanTitle = _cleanTitle(track.title);
    final cleanArtist = _cleanArtist(track.author);

    // 1. Exact query
    var uri = Uri.parse(
      'https://lrclib.net/api/get?track_name=${Uri.encodeComponent(cleanTitle)}&artist_name=${Uri.encodeComponent(cleanArtist)}',
    );
    if (track.duration > Duration.zero) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'duration': track.duration.inSeconds.toString(),
        },
      );
    }

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final synced = json['syncedLyrics'] as String?;
        if (synced != null && synced.trim().isNotEmpty) {
          return await _parseLrc(synced, source: 'LRCLIB', settings: settings);
        }
        final plain = json['plainLyrics'] as String?;
        if (plain != null && plain.trim().isNotEmpty) {
          return await _parsePlainLyrics(plain, track.duration, source: 'LRCLIB', settings: settings);
        }
      }
    } catch (_) {}

    // 2. Search query fallback
    try {
      final searchUri = Uri.parse(
        'https://lrclib.net/api/search?q=${Uri.encodeComponent("$cleanTitle $cleanArtist")}',
      );
      final searchRes = await http.get(searchUri).timeout(const Duration(seconds: 4));
      if (searchRes.statusCode == 200) {
        final list = jsonDecode(searchRes.body) as List<dynamic>;
        for (final item in list) {
          if (item is Map) {
            final synced = item['syncedLyrics'] as String?;
            if (synced != null && synced.trim().isNotEmpty) {
              return await _parseLrc(synced, source: 'LRCLIB', settings: settings);
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  Future<LyricsData?> _fetchFromKuGou(Track track, {SettingsService? settings}) async {
    try {
      final cleanTitle = _cleanTitle(track.title);
      final cleanArtist = _cleanArtist(track.author);

      // 1. Search song
      final query = Uri.encodeComponent('$cleanTitle $cleanArtist'.trim());
      final searchUri = Uri.parse(
        'http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=$query&page=1&pagesize=3',
      );
      final searchRes = await http.get(searchUri).timeout(const Duration(seconds: 4));
      if (searchRes.statusCode != 200) return null;
      final searchJson = jsonDecode(searchRes.body);
      final infoList = searchJson['data']?['info'] as List?;
      if (infoList == null || infoList.isEmpty) return null;

      final songHash = infoList[0]['hash'] as String?;
      if (songHash == null || songHash.isEmpty) return null;

      // 2. Search lyric candidate
      final lyricSearchUri = Uri.parse(
        'http://lyrics.kugou.com/search?ver=1&man=yes&client=pc&hash=$songHash',
      );
      final lyricSearchRes = await http.get(lyricSearchUri).timeout(const Duration(seconds: 4));
      if (lyricSearchRes.statusCode != 200) return null;
      final lyricSearchJson = jsonDecode(lyricSearchRes.body);
      final candidates = lyricSearchJson['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;

      final cand = candidates[0];
      final id = cand['id'];
      final accesskey = cand['accesskey'];
      if (id == null || accesskey == null) return null;

      // 3. Download lyric content
      final downloadUri = Uri.parse(
        'http://lyrics.kugou.com/download?ver=1&client=pc&id=$id&accesskey=$accesskey&fmt=lrc&charset=utf8',
      );
      final downloadRes = await http.get(downloadUri).timeout(const Duration(seconds: 4));
      if (downloadRes.statusCode != 200) return null;
      final downloadJson = jsonDecode(downloadRes.body);
      final contentB64 = downloadJson['content'] as String?;
      if (contentB64 == null || contentB64.isEmpty) return null;

      final lrcString = utf8.decode(base64.decode(contentB64));
      return await _parseLrc(lrcString, source: 'KuGou', settings: settings);
    } catch (e) {
      debugPrint('LyricsService: KuGou fetch error: $e');
      return null;
    }
  }

  Future<LyricsData?> _fetchFromNetEase(Track track, {SettingsService? settings}) async {
    try {
      final cleanTitle = _cleanTitle(track.title);
      final cleanArtist = _cleanArtist(track.author);
      final query = Uri.encodeComponent('$cleanTitle $cleanArtist'.trim());

      final searchUri = Uri.parse(
        'http://music.163.com/api/cloudsearch/pc?s=$query&type=1&offset=0&limit=3',
      );
      final searchRes = await http.get(
        searchUri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
        },
      ).timeout(const Duration(seconds: 4));

      if (searchRes.statusCode != 200) return null;
      final searchJson = jsonDecode(utf8.decode(searchRes.bodyBytes));
      final songs = searchJson['result']?['songs'] as List?;
      if (songs == null || songs.isEmpty) return null;

      final songId = songs[0]['id'];
      if (songId == null) return null;

      final lyricUri = Uri.parse(
        'http://music.163.com/api/song/lyric?os=pc&id=$songId&lv=-1&kv=-1&tv=-1',
      );
      final lyricRes = await http.get(
        lyricUri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
        },
      ).timeout(const Duration(seconds: 4));

      if (lyricRes.statusCode != 200) return null;
      final lyricJson = jsonDecode(utf8.decode(lyricRes.bodyBytes));
      final lrc = lyricJson['lrc']?['lyric'] as String?;
      if (lrc != null && lrc.trim().isNotEmpty) {
        return await _parseLrc(lrc, source: 'NetEase', settings: settings);
      }
      final tlyric = lyricJson['tlyric']?['lyric'] as String?;
      if (tlyric != null && tlyric.trim().isNotEmpty) {
        return await _parseLrc(tlyric, source: 'NetEase', settings: settings);
      }
    } catch (e) {
      debugPrint('LyricsService: NetEase fetch error: $e');
    }
    return null;
  }

  Future<LyricsData?> _fetchFromSimpMusic(Track track, {SettingsService? settings}) async {
    final cleanTitle = _cleanTitle(track.title);
    final cleanArtist = _cleanArtist(track.author);

    // 1. Direct query by YouTube Video ID if available
    if (track.id.isNotEmpty && !track.id.startsWith('spotify:')) {
      try {
        final videoUri = Uri.parse('https://api-lyrics.simpmusic.org/v1/${track.id}');
        final res = await http.get(
          videoUri,
          headers: {
            'User-Agent': 'SimpMusicLyrics/1.0',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final json = jsonDecode(utf8.decode(res.bodyBytes));
          final dataList = json['data'] as List?;
          if (dataList != null && dataList.isNotEmpty) {
            final first = dataList[0];
            final synced = first['syncedLyrics'] as String?;
            if (synced != null && synced.trim().isNotEmpty) {
              return await _parseLrc(synced, source: 'SimpMusic', settings: settings);
            }
            final plain = first['plainLyric'] as String?;
            if (plain != null && plain.trim().isNotEmpty) {
              return await _parsePlainLyrics(plain, track.duration, source: 'SimpMusic', settings: settings);
            }
          }
        }
      } catch (e) {
        debugPrint('LyricsService: SimpMusic videoId query error: $e');
      }
    }

    // 2. Search query via SimpMusic
    try {
      final searchUri = Uri.parse(
        'https://api-lyrics.simpmusic.org/v1/search?q=${Uri.encodeComponent("$cleanTitle $cleanArtist")}&limit=3',
      );
      final res = await http.get(
        searchUri,
        headers: {
          'User-Agent': 'SimpMusicLyrics/1.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final json = jsonDecode(utf8.decode(res.bodyBytes));
        final dataList = json['data'] as List?;
        if (dataList != null && dataList.isNotEmpty) {
          for (final item in dataList) {
            final synced = item['syncedLyrics'] as String?;
            if (synced != null && synced.trim().isNotEmpty) {
              return await _parseLrc(synced, source: 'SimpMusic', settings: settings);
            }
            final plain = item['plainLyric'] as String?;
            if (plain != null && plain.trim().isNotEmpty) {
              return await _parsePlainLyrics(plain, track.duration, source: 'SimpMusic', settings: settings);
            }
            // If item has a videoId, fetch its lyrics
            final vid = item['videoId'] as String?;
            if (vid != null && vid.isNotEmpty) {
              try {
                final subRes = await http.get(
                  Uri.parse('https://api-lyrics.simpmusic.org/v1/$vid'),
                  headers: {
                    'User-Agent': 'SimpMusicLyrics/1.0',
                    'Accept': 'application/json',
                  },
                ).timeout(const Duration(seconds: 3));
                if (subRes.statusCode == 200) {
                  final subJson = jsonDecode(utf8.decode(subRes.bodyBytes));
                  final subData = subJson['data'] as List?;
                  if (subData != null && subData.isNotEmpty) {
                    final s = subData[0]['syncedLyrics'] as String?;
                    if (s != null && s.trim().isNotEmpty) {
                      return await _parseLrc(s, source: 'SimpMusic', settings: settings);
                    }
                    final p = subData[0]['plainLyric'] as String?;
                    if (p != null && p.trim().isNotEmpty) {
                      return await _parsePlainLyrics(p, track.duration, source: 'SimpMusic', settings: settings);
                    }
                  }
                }
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('LyricsService: SimpMusic search query error: $e');
    }

    // 3. Fallback to BetterLyrics TTML / LRC API
    try {
      final betterLyricsUri = Uri.parse(
        'https://lyrics-api.boidu.dev/getLyrics?s=${Uri.encodeComponent(cleanTitle)}&a=${Uri.encodeComponent(cleanArtist)}',
      );
      final res = await http.get(
        betterLyricsUri,
        headers: {'User-Agent': 'SimpMusicLyrics/1.0'},
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final json = jsonDecode(utf8.decode(res.bodyBytes));
        final ttml = json['ttml'] as String? ?? json['lyrics'] as String?;
        if (ttml != null && ttml.trim().isNotEmpty) {
          final parsed = await _parseTtml(ttml, source: 'BetterLyrics', settings: settings);
          if (parsed != null && parsed.isNotEmpty) {
            return parsed;
          }
        }
      }
    } catch (e) {
      debugPrint('LyricsService: BetterLyrics query error: $e');
    }

    return null;
  }

  Duration? _parseTtmlTimestamp(String raw) {
    var str = raw.trim().replaceAll('s', '');
    final parts = str.split(':');
    if (parts.length == 3) {
      final hours = int.tryParse(parts[0]) ?? 0;
      final minutes = int.tryParse(parts[1]) ?? 0;
      final secParts = parts[2].split('.');
      final seconds = int.tryParse(secParts[0]) ?? 0;
      final millis = secParts.length > 1
          ? (int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ?? 0)
          : 0;
      return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: millis);
    } else if (parts.length == 2) {
      final minutes = int.tryParse(parts[0]) ?? 0;
      final secParts = parts[1].split('.');
      final seconds = int.tryParse(secParts[0]) ?? 0;
      final millis = secParts.length > 1
          ? (int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ?? 0)
          : 0;
      return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
    } else if (parts.length == 1) {
      final secs = double.tryParse(parts[0]);
      if (secs != null) {
        return Duration(milliseconds: (secs * 1000).round());
      }
    }
    return null;
  }

  Future<LyricsData?> _parseTtml(
    String ttmlContent, {
    required String source,
    SettingsService? settings,
  }) async {
    try {
      final pRegex = RegExp(r'<p\b[^>]*begin="([^"]+)"[^>]*>(.*?)</p>', dotAll: true, caseSensitive: false);
      final rawLines = <({Duration time, String text})>[];

      for (final match in pRegex.allMatches(ttmlContent)) {
        final beginStr = match.group(1);
        final innerContent = match.group(2);
        if (beginStr == null || innerContent == null) continue;

        final time = _parseTtmlTimestamp(beginStr);
        if (time == null) continue;

        final stripped = innerContent
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll('&quot;', '"')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&#39;', "'")
            .replaceAll('&apos;', "'");
        final text = sanitizeLyricText(stripped);

        if (text.isNotEmpty) {
          rawLines.add((time: time, text: text));
        }
      }

      if (rawLines.isEmpty) return null;
      rawLines.sort((a, b) => a.time.compareTo(b.time));

      final jap = settings?.romanizeJapanese ?? true;
      final kor = settings?.romanizeKorean ?? true;
      final chn = settings?.romanizeChinese ?? true;
      final hin = settings?.romanizeHindi ?? true;

      final foreignTexts = rawLines
          .map((r) => r.text)
          .where((t) => LyricsRomanizer.hasForeign(
                t,
                japanese: jap,
                korean: kor,
                chinese: chn,
                hindi: hin,
              ))
          .toList();

      final hasForeignText = foreignTexts.isNotEmpty;
      Map<String, TransliterationResult> transliterated = {};
      if (hasForeignText) {
        transliterated = await LyricsRomanizer.batchTransliterate(
          foreignTexts,
          japanese: jap,
          korean: kor,
          chinese: chn,
          hindi: hin,
        );
      }

      final lines = <LyricLine>[];
      for (final r in rawLines) {
        final tr = transliterated[r.text];
        lines.add(LyricLine(
          timestamp: r.time,
          text: r.text,
          romanizedText: tr?.romanized,
          translationText: tr?.translation,
        ));
      }

      return LyricsData(
        lines: lines,
        isSynced: true,
        hasForeign: hasForeignText,
        source: source,
      );
    } catch (e) {
      debugPrint('LyricsService: _parseTtml error: $e');
      return null;
    }
  }

  Future<LyricsData?> _fetchFromYouTubeCaptions(String videoId, {SettingsService? settings}) async {
    try {
      final manifest = await _ytExplode.videos.closedCaptions.getManifest(videoId);
      if (manifest.tracks.isEmpty) return null;

      // 1. Strictly prioritize human-provided official subtitles
      ClosedCaptionTrackInfo? trackInfo;
      final humanTracks = manifest.tracks.where((t) => !t.isAutoGenerated).toList();
      if (humanTracks.isNotEmpty) {
        final humanEn = humanTracks.where((t) => t.language.code == 'en').toList();
        trackInfo = humanEn.isNotEmpty ? humanEn.first : humanTracks.first;
      } else {
        // 2. Only consider English auto-generated captions if available
        final enAuto = manifest.getByLanguage('en');
        if (enAuto.isNotEmpty) {
          trackInfo = enAuto.first;
        }
      }

      // Reject if no matching human or verified English track found (prevents mangled ASR)
      if (trackInfo == null) return null;

      final ccTrack = await _ytExplode.videos.closedCaptions.get(trackInfo);
      if (ccTrack.captions.isEmpty) return null;

      final rawCaptions = <({Duration offset, String text})>[];
      int garbledLineCount = 0;

      for (final caption in ccTrack.captions) {
        final sanitized = sanitizeLyricText(caption.text);
        if (sanitized.isNotEmpty) {
          // Detect squashed words (e.g. "inthecityofthedeadI")
          final words = sanitized.split(RegExp(r'\s+'));
          if (words.any((w) => w.length >= 20)) {
            garbledLineCount++;
          }
          rawCaptions.add((offset: caption.offset, text: sanitized));
        }
      }

      if (rawCaptions.isEmpty) return null;

      // Discard if auto-generated captions are mangled
      if (trackInfo.isAutoGenerated && (garbledLineCount > 0 && (garbledLineCount / rawCaptions.length) > 0.12)) {
        debugPrint('LyricsService: Discarded garbled auto-generated YouTube captions ($garbledLineCount garbled lines)');
        return null;
      }

      final jap = settings?.romanizeJapanese ?? true;
      final kor = settings?.romanizeKorean ?? true;
      final chn = settings?.romanizeChinese ?? true;
      final hin = settings?.romanizeHindi ?? true;

      final foreignTexts = rawCaptions
          .map((c) => c.text)
          .where((t) => LyricsRomanizer.hasForeign(
                t,
                japanese: jap,
                korean: kor,
                chinese: chn,
                hindi: hin,
              ))
          .toList();

      final hasForeignText = foreignTexts.isNotEmpty;
      Map<String, TransliterationResult> transliterated = {};
      if (hasForeignText) {
        transliterated = await LyricsRomanizer.batchTransliterate(
          foreignTexts,
          japanese: jap,
          korean: kor,
          chinese: chn,
          hindi: hin,
        );
      }

      final List<LyricLine> lines = [];
      for (final c in rawCaptions) {
        final tr = transliterated[c.text] ?? transliterated[c.text.trim()];
        String? romaji = tr?.romanized;
        if (romaji == null || romaji.isEmpty || romaji.toLowerCase() == c.text.trim().toLowerCase()) {
          if (LyricsRomanizer.hasForeign(c.text, japanese: jap, korean: kor, chinese: chn, hindi: hin)) {
            romaji = LyricsRomanizer.romanize(c.text, japanese: jap, korean: kor, chinese: chn, hindi: hin);
          }
        }
        lines.add(LyricLine(
          timestamp: c.offset,
          text: c.text,
          romanizedText: romaji,
          translationText: tr?.translation,
        ));
      }

      return LyricsData(
        lines: lines,
        isSynced: true,
        hasForeign: hasForeignText,
        source: trackInfo.isAutoGenerated ? 'YouTube Auto-Captions' : 'YouTube Subtitles',
      );
    } catch (_) {
      return null;
    }
  }

  /// Automatically calibrates the lyrics timing offset by detecting discrepancies
  /// between vocal onset in YouTube audio and the provider's first lyric timestamp.
  Future<LyricsData?> _autoAlignLyricsTiming(String videoId, LyricsData lyrics) async {
    try {
      if (lyrics.lines.isEmpty) return null;
      final manifest = await _ytExplode.videos.closedCaptions.getManifest(videoId);
      if (manifest.tracks.isEmpty) return null;

      ClosedCaptionTrackInfo? trackInfo;
      final human = manifest.tracks.where((t) => !t.isAutoGenerated).toList();
      if (human.isNotEmpty) {
        trackInfo = human.first;
      } else {
        final en = manifest.getByLanguage('en');
        trackInfo = en.isNotEmpty ? en.first : manifest.tracks.first;
      }

      final ccTrack = await _ytExplode.videos.closedCaptions.get(trackInfo);
      final validCaptions = ccTrack.captions.where((c) => sanitizeLyricText(c.text).isNotEmpty).toList();
      if (validCaptions.isEmpty) return null;

      final vocalOnset = validCaptions.first.offset;
      final firstLyricLine = lyrics.lines.firstWhere(
        (l) => l.text.trim().isNotEmpty,
        orElse: () => lyrics.lines.first,
      );
      final lyricStart = firstLyricLine.timestamp;

      final delta = vocalOnset - lyricStart;
      if (delta.inMilliseconds.abs() >= 800 && delta.inSeconds < 35 && delta.inSeconds > -15) {
        debugPrint('LyricsService: Auto-aligning timing offset by ${delta.inMilliseconds}ms for video $videoId');
        final shifted = lyrics.lines.map((l) {
          final newTime = l.timestamp + delta;
          return l.copyWith(timestamp: newTime < Duration.zero ? Duration.zero : newTime);
        }).toList();
        return lyrics.copyWith(lines: shifted);
      }
    } catch (e) {
      debugPrint('LyricsService: _autoAlignLyricsTiming error: $e');
    }
    return null;
  }

  /// Automatically generates synchronized timestamps for plain/unsynced lyrics
  /// by aligning clean lines to YouTube's closed caption speech markers.
  Future<LyricsData?> _autoSyncPlainLyricsWithCaptions(
    String videoId,
    LyricsData plainLyrics, {
    SettingsService? settings,
  }) async {
    try {
      if (plainLyrics.lines.isEmpty) return null;
      final manifest = await _ytExplode.videos.closedCaptions.getManifest(videoId);
      if (manifest.tracks.isEmpty) return null;

      ClosedCaptionTrackInfo? trackInfo;
      final human = manifest.tracks.where((t) => !t.isAutoGenerated).toList();
      if (human.isNotEmpty) {
        trackInfo = human.first;
      } else {
        final en = manifest.getByLanguage('en');
        trackInfo = en.isNotEmpty ? en.first : manifest.tracks.first;
      }

      final ccTrack = await _ytExplode.videos.closedCaptions.get(trackInfo);
      final validCaptions = ccTrack.captions
          .where((c) => sanitizeLyricText(c.text).isNotEmpty)
          .map((c) => (offset: c.offset, text: sanitizeLyricText(c.text).toLowerCase()))
          .toList();
      if (validCaptions.isEmpty) return null;

      final plainLines = plainLyrics.lines;
      final syncedLines = <LyricLine>[];

      int captionIndex = 0;
      final mappedTimes = <int, Duration>{};

      for (int i = 0; i < plainLines.length; i++) {
        final lineText = plainLines[i].text.toLowerCase().trim();
        final lineWords = lineText.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();

        int bestMatchIndex = -1;
        int bestScore = 0;

        final windowEnd = (captionIndex + 15 < validCaptions.length) ? captionIndex + 15 : validCaptions.length;
        for (int c = captionIndex; c < windowEnd; c++) {
          final capText = validCaptions[c].text;
          int score = 0;
          for (final word in lineWords) {
            if (capText.contains(word)) score++;
          }
          if (score > bestScore) {
            bestScore = score;
            bestMatchIndex = c;
          }
        }

        if (bestMatchIndex != -1 && bestScore >= 1) {
          mappedTimes[i] = validCaptions[bestMatchIndex].offset;
          captionIndex = bestMatchIndex + 1;
        }
      }

      if (mappedTimes.isNotEmpty) {
        final firstTime = mappedTimes.values.first;
        final lastTime = mappedTimes.values.last;

        for (int i = 0; i < plainLines.length; i++) {
          Duration time;
          if (mappedTimes.containsKey(i)) {
            time = mappedTimes[i]!;
          } else {
            int prevIdx = -1;
            int nextIdx = -1;
            for (int p = i - 1; p >= 0; p--) {
              if (mappedTimes.containsKey(p)) {
                prevIdx = p;
                break;
              }
            }
            for (int n = i + 1; n < plainLines.length; n++) {
              if (mappedTimes.containsKey(n)) {
                nextIdx = n;
                break;
              }
            }

            if (prevIdx != -1 && nextIdx != -1) {
              final t1 = mappedTimes[prevIdx]!;
              final t2 = mappedTimes[nextIdx]!;
              final fraction = (i - prevIdx) / (nextIdx - prevIdx);
              final diffMs = (t2 - t1).inMilliseconds;
              time = t1 + Duration(milliseconds: (diffMs * fraction).round());
            } else if (prevIdx != -1) {
              time = mappedTimes[prevIdx]! + Duration(seconds: (i - prevIdx) * 3);
            } else if (nextIdx != -1) {
              final t2 = mappedTimes[nextIdx]!;
              final backMs = (nextIdx - i) * 3000;
              time = t2.inMilliseconds > backMs ? t2 - Duration(milliseconds: backMs) : Duration.zero;
            } else {
              final fraction = i / (plainLines.length > 1 ? plainLines.length - 1 : 1);
              final spanMs = (lastTime - firstTime).inMilliseconds;
              time = firstTime + Duration(milliseconds: (spanMs * fraction).round());
            }
          }

          syncedLines.add(plainLines[i].copyWith(timestamp: time));
        }
      } else {
        final firstTime = validCaptions.first.offset;
        final lastTime = validCaptions.last.offset;
        final spanMs = (lastTime - firstTime).inMilliseconds;

        for (int i = 0; i < plainLines.length; i++) {
          final fraction = i / (plainLines.length > 1 ? plainLines.length - 1 : 1);
          final time = firstTime + Duration(milliseconds: (spanMs * fraction).round());
          syncedLines.add(plainLines[i].copyWith(timestamp: time));
        }
      }

      return plainLyrics.copyWith(
        lines: syncedLines,
        isSynced: true,
        source: '${plainLyrics.source ?? "Lyrics"} (Auto-Synced)',
      );
    } catch (e) {
      debugPrint('LyricsService: _autoSyncPlainLyricsWithCaptions error: $e');
    }
    return null;
  }

  Future<LyricsData> _parseLrc(
    String lrcContent, {
    required String source,
    SettingsService? settings,
  }) async {
    final rawLines = <({Duration time, String text})>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.?(\d{2,3})?\](.*)');
    final jap = settings?.romanizeJapanese ?? true;
    final kor = settings?.romanizeKorean ?? true;
    final chn = settings?.romanizeChinese ?? true;
    final hin = settings?.romanizeHindi ?? true;

    for (final rawLine in lrcContent.split('\n')) {
      final match = regex.firstMatch(rawLine.trim());
      if (match != null) {
        final mins = int.tryParse(match.group(1) ?? '0') ?? 0;
        final secs = int.tryParse(match.group(2) ?? '0') ?? 0;
        final millisStr = match.group(3) ?? '0';
        final millis = int.tryParse(millisStr.padRight(3, '0').substring(0, 3)) ?? 0;
        final time = Duration(minutes: mins, seconds: secs, milliseconds: millis);
        final rawText = match.group(4)?.trim() ?? '';
        final text = sanitizeLyricText(rawText);

        if (text.isNotEmpty) {
          rawLines.add((time: time, text: text));
        }
      }
    }

    rawLines.sort((a, b) => a.time.compareTo(b.time));

    final foreignTexts = rawLines
        .map((r) => r.text)
        .where((t) => LyricsRomanizer.hasForeign(
              t,
              japanese: jap,
              korean: kor,
              chinese: chn,
              hindi: hin,
            ))
        .toList();

    final hasForeignText = foreignTexts.isNotEmpty;
    Map<String, TransliterationResult> transliterated = {};
    if (hasForeignText) {
      transliterated = await LyricsRomanizer.batchTransliterate(
        foreignTexts,
        japanese: jap,
        korean: kor,
        chinese: chn,
        hindi: hin,
      );
    }

    final lines = <LyricLine>[];
    for (final r in rawLines) {
      final tr = transliterated[r.text] ?? transliterated[r.text.trim()];
      String? romaji = tr?.romanized;
      if (romaji == null || romaji.isEmpty || romaji.toLowerCase() == r.text.trim().toLowerCase()) {
        if (LyricsRomanizer.hasForeign(r.text, japanese: jap, korean: kor, chinese: chn, hindi: hin)) {
          romaji = LyricsRomanizer.romanize(r.text, japanese: jap, korean: kor, chinese: chn, hindi: hin);
        }
      }
      lines.add(LyricLine(
        timestamp: r.time,
        text: r.text,
        romanizedText: romaji,
        translationText: tr?.translation,
      ));
    }

    return LyricsData(
      lines: lines,
      isSynced: true,
      hasForeign: hasForeignText,
      source: source,
    );
  }

  Future<LyricsData> _parsePlainLyrics(
    String text,
    Duration totalDuration, {
    required String source,
    SettingsService? settings,
  }) async {
    final rawLines = text
        .split('\n')
        .map((l) => sanitizeLyricText(l))
        .where((l) => l.isNotEmpty)
        .toList();
    if (rawLines.isEmpty) return const LyricsData(lines: [], isSynced: false);

    final lines = <LyricLine>[];
    final jap = settings?.romanizeJapanese ?? true;
    final kor = settings?.romanizeKorean ?? true;
    final chn = settings?.romanizeChinese ?? true;
    final hin = settings?.romanizeHindi ?? true;

    final foreignTexts = rawLines
        .where((t) => LyricsRomanizer.hasForeign(
              t,
              japanese: jap,
              korean: kor,
              chinese: chn,
              hindi: hin,
            ))
        .toList();

    final hasForeignText = foreignTexts.isNotEmpty;
    Map<String, TransliterationResult> transliterated = {};
    if (hasForeignText) {
      transliterated = await LyricsRomanizer.batchTransliterate(
        foreignTexts,
        japanese: jap,
        korean: kor,
        chinese: chn,
        hindi: hin,
      );
    }

    // For plain unsynced lyrics, avoid fake incrementing timestamps that trigger erratic auto-scrolling
    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i];
      final tr = transliterated[line] ?? transliterated[line.trim()];
      String? romaji = tr?.romanized;
      if (romaji == null || romaji.isEmpty || romaji.toLowerCase() == line.trim().toLowerCase()) {
        if (LyricsRomanizer.hasForeign(line, japanese: jap, korean: kor, chinese: chn, hindi: hin)) {
          romaji = LyricsRomanizer.romanize(line, japanese: jap, korean: kor, chinese: chn, hindi: hin);
        }
      }
      lines.add(LyricLine(
        timestamp: Duration.zero,
        text: line,
        romanizedText: romaji,
        translationText: tr?.translation,
      ));
    }

    return LyricsData(
      lines: lines,
      isSynced: false,
      hasForeign: hasForeignText,
      source: source,
    );
  }

  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'【.*?】'), '')
        .replaceAll(RegExp(r'\(.*?official.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?official.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(.*?video.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?video.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(.*?mv.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?mv.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(.*?audio.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?audio.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(.*?lyrics.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?lyrics.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(feat\..*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[feat\..*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(ft\..*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[ft\..*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(prod\..*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[prod\..*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanArtist(String artist) {
    var cleaned = artist
        .replaceAll(RegExp(r' - Topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
        .trim();
    if (cleaned.contains(';')) {
      cleaned = cleaned.split(';').first.trim();
    } else if (cleaned.toLowerCase().contains(' feat. ')) {
      cleaned = cleaned.split(RegExp(r'\s+feat\.\s+', caseSensitive: false)).first.trim();
    } else if (cleaned.toLowerCase().contains(' ft. ')) {
      cleaned = cleaned.split(RegExp(r'\s+ft\.\s+', caseSensitive: false)).first.trim();
    }
    return cleaned;
  }

  void dispose() {
    _ytExplode.close();
  }
}
