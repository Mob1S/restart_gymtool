enum MotionView { front, side, oblique }

extension MotionViewLabel on MotionView {
  String get label => switch (this) {
    MotionView.front => '正面',
    MotionView.side => '侧面',
    MotionView.oblique => '斜侧面',
  };
}

enum MotionCapability { validated, experimental, unavailable }

class MotionProfile {
  final String id, name, equipment, bodyPart, category, description;
  final int version;
  final String? variationOf;
  final List<String> landmarks, trajectoryTargets, phases, exclusions;
  final Map<MotionView, String> viewAdvice;
  final Map<MotionView, MotionCapability> views;
  final List<String> candidateObservations;
  final String analyzerId;
  final int analyzerVersion, resultVersion;
  final List<String> modelDependencies;
  const MotionProfile({
    required this.id,
    required this.name,
    required this.equipment,
    required this.bodyPart,
    required this.category,
    required this.description,
    this.version = 1,
    this.variationOf,
    required this.landmarks,
    required this.trajectoryTargets,
    required this.phases,
    required this.exclusions,
    required this.viewAdvice,
    required this.views,
    required this.candidateObservations,
    this.analyzerId = 'pose_cycle_candidates',
    this.analyzerVersion = 1,
    this.resultVersion = 3,
    this.modelDependencies = const ['mediapipe_pose_lite'],
  });
  MotionCapability capability(MotionView view) =>
      views[view] ?? MotionCapability.unavailable;
  bool get hasBarbell => equipment == '杠铃';
}

class MotionCatalog {
  static const bench = 'barbell_bench_press';
  static const squat = 'barbell_squat';
  static const deadlift = 'barbell_deadlift';
  static const pullUp = 'bodyweight_pull_up';

  static const profiles = <MotionProfile>[
    MotionProfile(
      id: squat,
      name: '杠铃深蹲',
      equipment: '杠铃',
      bodyPart: '腿部',
      category: '蹲',
      description: '站立、下蹲并返回站立。全身及杠铃尽量持续入镜。',
      landmarks: ['肩', '髋', '膝', '踝'],
      trajectoryTargets: ['髋', '膝', '踝', '躯干', '可见杠铃'],
      phases: ['站立', '下蹲', '底部', '返回站立'],
      exclusions: ['准备', '半次', '失去可见性'],
      viewAdvice: {
        MotionView.side: '侧面可观察深度和躯干；固定机位，拍摄全身。',
        MotionView.front: '正面可观察左右变化；固定机位，拍摄全身。',
        MotionView.oblique: '斜侧面有透视误差，请保证双侧关键关节入镜。',
      },
      views: {
        MotionView.side: MotionCapability.experimental,
        MotionView.front: MotionCapability.experimental,
        MotionView.oblique: MotionCapability.experimental,
      },
      candidateObservations: ['下蹲幅度', '躯干姿态变化', '重复间一致性'],
    ),
    MotionProfile(
      id: bench,
      analyzerId: 'barbell_lk_cycle',
      modelDependencies: ['mediapipe_pose_lite', 'opencv_lk_tracker'],
      name: '杠铃卧推',
      equipment: '杠铃',
      bodyPart: '胸部',
      category: '推',
      description: '杠铃下降并推起完成。现有侧面流程需要标记近侧杠铃片中心。',
      landmarks: ['肩', '肘', '腕'],
      trajectoryTargets: ['肩', '肘', '腕', '近侧杠铃片中心'],
      phases: ['顶部', '下降', '底部', '推起完成'],
      exclusions: ['准备', '回架', '半次', '轨迹缺口'],
      viewAdvice: {
        MotionView.side: '固定手机，从侧面拍摄；让近侧杠铃片与上半身全程入镜。',
        MotionView.front: '正面易有器械和人体遮挡，当前不输出自动次数。',
        MotionView.oblique: '斜侧面有透视误差，当前不输出自动次数。',
      },
      views: {
        MotionView.side: MotionCapability.experimental,
        MotionView.front: MotionCapability.unavailable,
        MotionView.oblique: MotionCapability.unavailable,
      },
      candidateObservations: ['动作幅度', '杠铃路径', '重复间一致性'],
    ),
    MotionProfile(
      id: deadlift,
      name: '杠铃硬拉',
      equipment: '杠铃',
      bodyPart: '背部',
      category: '拉',
      description: '杠铃离地、站直并回到起始位置。全身及杠铃尽量持续入镜。',
      landmarks: ['肩', '腕', '髋', '膝', '踝'],
      trajectoryTargets: ['肩', '腕', '髋', '膝', '踝', '可见杠铃'],
      phases: ['起始', '离地', '站直', '返回起始'],
      exclusions: ['准备', '半次', '失去可见性'],
      viewAdvice: {
        MotionView.side: '侧面可观察前后路径及髋部变化。',
        MotionView.front: '正面可观察左右偏移，须保持双侧入镜。',
        MotionView.oblique: '斜侧面透视会影响路径判断。',
      },
      views: {
        MotionView.side: MotionCapability.experimental,
        MotionView.front: MotionCapability.experimental,
        MotionView.oblique: MotionCapability.experimental,
      },
      candidateObservations: ['躯干姿态变化', '杠铃相对身体路径', '重复间一致性'],
    ),
    MotionProfile(
      id: pullUp,
      name: '自重引体向上',
      equipment: '自重',
      bodyPart: '背部',
      category: '拉',
      description: '从悬垂上拉至顶点，再返回底部。拍摄横杠及全身。',
      landmarks: ['头', '肩', '肘', '腕', '髋'],
      trajectoryTargets: ['肩', '肘', '腕', '髋', '头与躯干'],
      phases: ['悬垂', '上拉', '顶点', '返回悬垂'],
      exclusions: ['准备', '半次', '失去可见性'],
      viewAdvice: {
        MotionView.side: '侧面可观察身体摆动和幅度。',
        MotionView.front: '正面可观察双侧运动。',
        MotionView.oblique: '斜侧面可补充观察，注意透视和遮挡。',
      },
      views: {
        MotionView.side: MotionCapability.experimental,
        MotionView.front: MotionCapability.experimental,
        MotionView.oblique: MotionCapability.experimental,
      },
      candidateObservations: ['动作幅度', '身体摆动', '重复间一致性'],
    ),
  ];

  static MotionProfile byId(String? id) {
    if (id == null) {
      return profiles[1]; // v1/v2 saved projects are side-view bench press.
    }
    return profiles.firstWhere(
      (profile) => profile.id == id,
      orElse: () => MotionProfile(
        id: id,
        name: '未知动作',
        equipment: '未知',
        bodyPart: '未知',
        category: '未知',
        description: '此版本没有该动作档案，原分析数据仍保留。',
        landmarks: const [],
        trajectoryTargets: const [],
        phases: const [],
        exclusions: const [],
        viewAdvice: const {},
        views: const {},
        candidateObservations: const [],
      ),
    );
  }
}
