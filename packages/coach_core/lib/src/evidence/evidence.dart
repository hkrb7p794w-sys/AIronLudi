import '../coach/recommendation.dart';

/// Art einer Veröffentlichung.
enum StudyKind {
  metaAnalysis('Metaanalyse'),
  systematicReview('Systematisches Review'),
  review('Review'),
  consensus('Konsens/Leitlinie'),
  trial('Randomisierte Studie'),
  cohort('Kohortenstudie'),
  study('Studie');

  const StudyKind(this.rawValue);

  final String rawValue;
}

/// Eine Veröffentlichung, auf die sich eine Regel stützt. DOIs am 26.10.2026 in PubMed geprüft.
final class Study {
  const Study({
    required this.id,
    required this.citation,
    required this.title,
    required this.journal,
    required this.doi,
    required this.pmid,
    required this.kind,
  });

  final String id;

  /// „Helgerud et al. 2007“
  final String citation;
  final String title;
  final String journal;
  final String? doi;
  final String pmid;
  final StudyKind kind;

  Uri get url => doi != null ? Uri.parse('https://doi.org/$doi') : Uri.parse('https://pubmed.ncbi.nlm.nih.gov/$pmid/');

  @override
  String toString() => 'Study($id)';
}

/// Wie gut eine Regel gestützt ist – ehrlich statt Pseudo-Präzision.
enum EvidenceStrength {
  /// Metaanalysen, systematische Reviews oder Leitlinien stützen die Aussage direkt.
  strong('gut belegt'),

  /// Einzelstudien oder Reviews stützen die Richtung; Schwellenwerte sind Praxiswerte.
  moderate('belegt, Schwellen aus der Praxis'),

  /// Praxisregel: plausibel und vorsichtig, aber ohne direkte Studie für genau diesen Wert.
  practice('Praxisregel');

  const EvidenceStrength(this.rawValue);

  final String rawValue;
}

/// Eine Regel der App mit ihrer Begründung.
final class EvidenceRule {
  const EvidenceRule({
    required this.id,
    required this.title,
    required this.statement,
    required this.strength,
    required this.studyIDs,
  });

  final String id;
  final String title;

  /// Kernaussage in einem Satz – dieser Satz geht auch an die KI.
  final String statement;
  final EvidenceStrength strength;
  final List<String> studyIDs;

  List<Study> get studies => [for (final id in studyIDs) ?Evidence.studiesByID[id]];

  @override
  String toString() => 'EvidenceRule($id)';
}

/// Alle Quellen und Regeln an einer Stelle. Neue Regeln nur mit geprüfter Quelle (PubMed/DOI) ergänzen.
abstract final class Evidence {
  // dart format off
  static const List<Study> studies = [
    Study(id: 'plews2012', citation: 'Plews et al. 2012', title: 'Heart rate variability in elite triathletes, is variation in variability the key to effective training? A case comparison.', journal: 'Eur J Appl Physiol', doi: '10.1007/s00421-012-2354-4', pmid: '22367011', kind: StudyKind.study),
    Study(id: 'plews2013', citation: 'Plews et al. 2013', title: 'Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring.', journal: 'Sports Med', doi: '10.1007/s40279-013-0071-8', pmid: '23852425', kind: StudyKind.review),
    Study(id: 'buchheit2014', citation: 'Buchheit 2014', title: 'Monitoring training status with HR measures: do all roads lead to Rome?', journal: 'Front Physiol', doi: '10.3389/fphys.2014.00073', pmid: '24578692', kind: StudyKind.review),
    Study(id: 'saw2016', citation: 'Saw et al. 2016', title: 'Monitoring the athlete training response: subjective self-reported measures trump commonly used objective measures: a systematic review.', journal: 'Br J Sports Med', doi: '10.1136/bjsports-2015-094758', pmid: '26423706', kind: StudyKind.systematicReview),
    Study(id: 'foster2001', citation: 'Foster et al. 2001', title: 'A new approach to monitoring exercise training.', journal: 'J Strength Cond Res', doi: null, pmid: '11708692', kind: StudyKind.study),
    Study(id: 'seiler2006', citation: 'Seiler & Kjerland 2006', title: 'Quantifying training intensity distribution in elite endurance athletes: is there evidence for an "optimal" distribution?', journal: 'Scand J Med Sci Sports', doi: '10.1111/j.1600-0838.2004.00418.x', pmid: '16430681', kind: StudyKind.study),
    Study(id: 'esteveLanao2007', citation: 'Esteve-Lanao et al. 2007', title: 'Impact of training intensity distribution on performance in endurance athletes.', journal: 'J Strength Cond Res', doi: '10.1519/R-19725.1', pmid: '17685689', kind: StudyKind.trial),
    Study(id: 'munoz2014', citation: 'Muñoz et al. 2014', title: 'Does polarized training improve performance in recreational runners?', journal: 'Int J Sports Physiol Perform', doi: '10.1123/ijspp.2012-0350', pmid: '23752040', kind: StudyKind.trial),
    Study(id: 'rosenblat2025', citation: 'Rosenblat et al. 2025', title: 'Which Training Intensity Distribution Intervention will Produce the Greatest Improvements in Maximal Oxygen Uptake and Time-Trial Performance in Endurance Athletes?', journal: 'Sports Med', doi: '10.1007/s40279-024-02149-3', pmid: '39888556', kind: StudyKind.metaAnalysis),
    Study(id: 'helgerud2007', citation: 'Helgerud et al. 2007', title: 'Aerobic high-intensity intervals improve VO2max more than moderate training.', journal: 'Med Sci Sports Exerc', doi: '10.1249/mss.0b013e3180304570', pmid: '17414804', kind: StudyKind.trial),
    Study(id: 'nes2013', citation: 'Nes et al. 2013', title: 'Age-predicted maximal heart rate in healthy subjects: The HUNT fitness study.', journal: 'Scand J Med Sci Sports', doi: '10.1111/j.1600-0838.2012.01445.x', pmid: '22376273', kind: StudyKind.cohort),
    Study(id: 'neudorfer2024', citation: 'Neudorfer et al. 2024', title: 'Validity of Four Consumer-Grade Optical Heart Rate Sensors for Assessing Volume and Intensity Distribution of Physical Activity.', journal: 'Scand J Med Sci Sports', doi: '10.1111/sms.14756', pmid: '39508366', kind: StudyKind.study),
    Study(id: 'ronnestad2013', citation: 'Rønnestad & Mujika 2013', title: 'Optimizing strength training for running and cycling endurance performance: A review.', journal: 'Scand J Med Sci Sports', doi: '10.1111/sms.12104', pmid: '23914932', kind: StudyKind.review),
    Study(id: 'denadai2017', citation: 'Denadai et al. 2017', title: 'Explosive Training and Heavy Weight Training are Effective for Improving Running Economy in Endurance Athletes: A Systematic Review and Meta-Analysis.', journal: 'Sports Med', doi: '10.1007/s40279-016-0604-z', pmid: '27497600', kind: StudyKind.metaAnalysis),
    Study(id: 'blagrove2018', citation: 'Blagrove et al. 2018', title: 'Effects of Strength Training on the Physiological Determinants of Middle- and Long-Distance Running Performance: A Systematic Review.', journal: 'Sports Med', doi: '10.1007/s40279-017-0835-7', pmid: '29249083', kind: StudyKind.systematicReview),
    Study(id: 'wilson2012', citation: 'Wilson et al. 2012', title: 'Concurrent training: a meta-analysis examining interference of aerobic and resistance exercises.', journal: 'J Strength Cond Res', doi: '10.1519/JSC.0b013e31823a3e2d', pmid: '22002517', kind: StudyKind.metaAnalysis),
    Study(id: 'murlasits2017', citation: 'Murlasits et al. 2017', title: 'The physiological effects of concurrent strength and endurance training sequence: A systematic review and meta-analysis.', journal: 'J Sports Sci', doi: '10.1080/02640414.2017.1364405', pmid: '28783467', kind: StudyKind.metaAnalysis),
    Study(id: 'huiberts2023', citation: 'Huiberts et al. 2023', title: 'Concurrent Strength and Endurance Training: A Systematic Review and Meta-Analysis on the Impact of Sex and Training Status.', journal: 'Sports Med', doi: '10.1007/s40279-023-01943-9', pmid: '37847373', kind: StudyKind.metaAnalysis),
    Study(id: 'acsm2009', citation: 'ACSM 2009', title: 'American College of Sports Medicine position stand. Progression models in resistance training for healthy adults.', journal: 'Med Sci Sports Exerc', doi: '10.1249/MSS.0b013e3181915670', pmid: '19204579', kind: StudyKind.consensus),
    Study(id: 'currier2026', citation: 'Currier et al. 2026 (ACSM)', title: 'American College of Sports Medicine Position Stand. Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in Healthy Adults: An Overview of Reviews.', journal: 'Med Sci Sports Exerc', doi: '10.1249/MSS.0000000000003897', pmid: '41843416', kind: StudyKind.consensus),
    Study(id: 'schoenfeld2017', citation: 'Schoenfeld et al. 2017', title: 'Dose-response relationship between weekly resistance training volume and increases in muscle mass: A systematic review and meta-analysis.', journal: 'J Sports Sci', doi: '10.1080/02640414.2016.1210197', pmid: '27433992', kind: StudyKind.metaAnalysis),
    Study(id: 'pelland2025', citation: 'Pelland et al. 2025', title: 'The Resistance Training Dose Response: Meta-Regressions Exploring the Effects of Weekly Volume and Frequency on Muscle Hypertrophy and Strength Gains.', journal: 'Sports Med', doi: '10.1007/s40279-025-02344-w', pmid: '41343037', kind: StudyKind.metaAnalysis),
    Study(id: 'wang2023', citation: 'Wang et al. 2023', title: 'Effects of tapering on performance in endurance athletes: A systematic review and meta-analysis.', journal: 'PLoS One', doi: '10.1371/journal.pone.0282838', pmid: '37163550', kind: StudyKind.metaAnalysis),
    Study(id: 'ainsworth2011', citation: 'Ainsworth et al. 2011', title: '2011 Compendium of Physical Activities: a second update of codes and MET values.', journal: 'Med Sci Sports Exerc', doi: '10.1249/MSS.0b013e31821ece12', pmid: '21681120', kind: StudyKind.study),
    Study(id: 'gilmore2014', citation: 'Gilmore et al. 2014', title: 'An objective estimate of energy intake during weight gain using the intake-balance method.', journal: 'Am J Clin Nutr', doi: '10.3945/ajcn.114.087122', pmid: '25057153', kind: StudyKind.trial),
    Study(id: 'sanghvi2015', citation: 'Sanghvi et al. 2015', title: 'Validation of an inexpensive and accurate mathematical method to measure long-term changes in free-living energy intake.', journal: 'Am J Clin Nutr', doi: '10.3945/ajcn.115.111070', pmid: '26040640', kind: StudyKind.study),
    Study(id: 'lichtman1992', citation: 'Lichtman et al. 1992', title: 'Discrepancy between self-reported and actual caloric intake and exercise in obese subjects.', journal: 'N Engl J Med', doi: '10.1056/NEJM199212313272701', pmid: '1454084', kind: StudyKind.study),
    Study(id: 'clarke2013', citation: 'Clarke & Skiba 2013', title: 'Rationale and resources for teaching the mathematical modeling of athletic training and performance.', journal: 'Adv Physiol Educ', doi: '10.1152/advan.00078.2011', pmid: '23728131', kind: StudyKind.review),
    Study(id: 'impellizzeri2020', citation: 'Impellizzeri et al. 2020', title: 'Acute:Chronic Workload Ratio: Conceptual Issues and Fundamental Pitfalls.', journal: 'Int J Sports Physiol Perform', doi: '10.1123/ijspp.2019-0864', pmid: '32502973', kind: StudyKind.review),
    Study(id: 'mah2011', citation: 'Mah et al. 2011', title: 'The effects of sleep extension on the athletic performance of collegiate basketball players.', journal: 'Sleep', doi: '10.5665/SLEEP.1132', pmid: '21731144', kind: StudyKind.study),
    Study(id: 'mifflin1990', citation: 'Mifflin et al. 1990', title: 'A new predictive equation for resting energy expenditure in healthy individuals.', journal: 'Am J Clin Nutr', doi: '10.1093/ajcn/51.2.241', pmid: '2305711', kind: StudyKind.study),
    Study(id: 'thomas2016', citation: 'Thomas et al. 2016 (ACSM/AND/DC)', title: 'American College of Sports Medicine Joint Position Statement. Nutrition and Athletic Performance.', journal: 'Med Sci Sports Exerc', doi: '10.1249/MSS.0000000000000852', pmid: '26891166', kind: StudyKind.consensus),
    Study(id: 'jaeger2017', citation: 'Jäger et al. 2017 (ISSN)', title: 'International Society of Sports Nutrition Position Stand: protein and exercise.', journal: 'J Int Soc Sports Nutr', doi: '10.1186/s12970-017-0177-8', pmid: '28642676', kind: StudyKind.consensus),
    Study(id: 'mountjoy2023', citation: 'Mountjoy et al. 2023 (IOC)', title: '2023 International Olympic Committee\'s (IOC) consensus statement on Relative Energy Deficiency in Sport (REDs).', journal: 'Br J Sports Med', doi: '10.1136/bjsports-2023-106994', pmid: '37752011', kind: StudyKind.consensus),
    Study(id: 'watson2015', citation: 'Watson et al. 2015 (AASM/SRS)', title: 'Recommended Amount of Sleep for a Healthy Adult: A Joint Consensus Statement of the American Academy of Sleep Medicine and Sleep Research Society.', journal: 'Sleep', doi: '10.5665/sleep.4716', pmid: '26039963', kind: StudyKind.consensus),
    Study(id: 'fullagar2015', citation: 'Fullagar et al. 2015', title: 'Sleep and athletic performance: the effects of sleep loss on exercise performance, and physiological and cognitive responses to exercise.', journal: 'Sports Med', doi: '10.1007/s40279-014-0260-0', pmid: '25315456', kind: StudyKind.review),
    Study(id: 'walsh2021', citation: 'Walsh et al. 2021', title: 'Sleep and the athlete: narrative review and 2021 expert consensus recommendations.', journal: 'Br J Sports Med', doi: '10.1136/bjsports-2020-102025', pmid: '33144349', kind: StudyKind.consensus),
    Study(id: 'wakayoshi1992', citation: 'Wakayoshi et al. 1992', title: 'A simple method for determining critical speed as swimming fatigue threshold in competitive swimming.', journal: 'Int J Sports Med', doi: '10.1055/s-2007-1021282', pmid: '1521952', kind: StudyKind.study),
    Study(id: 'coyle2001', citation: 'Coyle & González-Alonso 2001', title: 'Cardiovascular drift during prolonged exercise: new perspectives.', journal: 'Exerc Sport Sci Rev', doi: '10.1097/00003677-200104000-00009', pmid: '11337829', kind: StudyKind.review),
    Study(id: 'maunder2021', citation: 'Maunder et al. 2021', title: 'The Importance of \'Durability\' in the Physiological Profiling of Endurance Athletes.', journal: 'Sports Med', doi: '10.1007/s40279-021-01459-0', pmid: '33886100', kind: StudyKind.review),
    Study(id: 'bull2020', citation: 'Bull et al. 2020 (WHO)', title: 'World Health Organization 2020 guidelines on physical activity and sedentary behaviour.', journal: 'Br J Sports Med', doi: '10.1136/bjsports-2020-102955', pmid: '33239350', kind: StudyKind.consensus),
    Study(id: 'donnelly2009', citation: 'Donnelly et al. 2009 (ACSM)', title: 'American College of Sports Medicine Position Stand. Appropriate physical activity intervention strategies for weight loss and prevention of weight regain for adults.', journal: 'Med Sci Sports Exerc', doi: '10.1249/MSS.0b013e3181949333', pmid: '19127177', kind: StudyKind.consensus),
    Study(id: 'swift2014', citation: 'Swift et al. 2014', title: 'The role of exercise and physical activity in weight loss and maintenance.', journal: 'Prog Cardiovasc Dis', doi: '10.1016/j.pcad.2013.09.012', pmid: '24438736', kind: StudyKind.review),
    Study(id: 'garthe2011', citation: 'Garthe et al. 2011', title: 'Long-term effect of weight loss on body composition and performance in elite athletes.', journal: 'Int J Sport Nutr Exerc Metab', doi: '10.1123/ijsnem.21.5.426', pmid: '21896944', kind: StudyKind.trial),
    Study(id: 'hudson2020', citation: 'Hudson et al. 2020', title: 'Protein Intake Greater than the RDA Differentially Influences Whole-Body Lean Mass Responses to Purposeful Catabolic and Anabolic Stressors: A Systematic Review and Meta-analysis.', journal: 'Adv Nutr', doi: '10.1093/advances/nmz106', pmid: '31794597', kind: StudyKind.metaAnalysis),
    Study(id: 'morton2018', citation: 'Morton et al. 2018', title: 'A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength in healthy adults.', journal: 'Br J Sports Med', doi: '10.1136/bjsports-2017-097608', pmid: '28698222', kind: StudyKind.metaAnalysis),
    Study(id: 'larsonmeyer2022', citation: 'Larson-Meyer et al. 2022', title: 'Weight Gain Recommendations for Athletes and Military Personnel: a Critical Review of the Evidence.', journal: 'Curr Nutr Rep', doi: '10.1007/s13668-022-00395-3', pmid: '35233712', kind: StudyKind.review),
    Study(id: 'nedeltcheva2010', citation: 'Nedeltcheva et al. 2010', title: 'Insufficient sleep undermines dietary efforts to reduce adiposity.', journal: 'Ann Intern Med', doi: '10.7326/0003-4819-153-7-201010050-00006', pmid: '20921542', kind: StudyKind.trial),
    Study(id: 'buist2007', citation: 'Buist et al. 2007', title: 'No effect of a graded training program on the number of running-related injuries in novice runners: a randomized controlled trial.', journal: 'Am J Sports Med', doi: '10.1177/0363546507307505', pmid: '17940147', kind: StudyKind.trial),
    Study(id: 'frandsen2025', citation: 'Frandsen et al. 2025', title: 'How much running is too much? Identifying high-risk running sessions in a 5200-person cohort study.', journal: 'Br J Sports Med', doi: '10.1136/bjsports-2024-109380', pmid: '40623829', kind: StudyKind.cohort),
    Study(id: 'nielsen2014', citation: 'Nielsen et al. 2014', title: 'Excessive progression in weekly running distance and risk of running-related injuries: an association which varies according to type of injury.', journal: 'J Orthop Sports Phys Ther', doi: '10.2519/jospt.2014.5164', pmid: '25155475', kind: StudyKind.cohort),
    Study(id: 'hespanhol2015', citation: 'Hespanhol Junior et al. 2015', title: 'Meta-Analyses of the Effects of Habitual Running on Indices of Health in Physically Inactive Adults.', journal: 'Sports Med', doi: '10.1007/s40279-015-0359-y', pmid: '26178328', kind: StudyKind.metaAnalysis),
    Study(id: 'reimers2018', citation: 'Reimers et al. 2018', title: 'Effects of Exercise on the Resting Heart Rate: A Systematic Review and Meta-Analysis of Interventional Studies.', journal: 'J Clin Med', doi: '10.3390/jcm7120503', pmid: '30513777', kind: StudyKind.metaAnalysis),
    Study(id: 'milanovic2015', citation: 'Milanović et al. 2015', title: 'Effectiveness of High-Intensity Interval Training (HIT) and Continuous Endurance Training for VO2max Improvements: A Systematic Review and Meta-Analysis of Controlled Trials.', journal: 'Sports Med', doi: '10.1007/s40279-015-0365-0', pmid: '26243014', kind: StudyKind.metaAnalysis),
    Study(id: 'pedisic2019', citation: 'Pedisic et al. 2019', title: 'Is running associated with a lower risk of all-cause, cardiovascular and cancer mortality, and is the more the better? A systematic review and meta-analysis.', journal: 'Br J Sports Med', doi: '10.1136/bjsports-2018-100493', pmid: '31685526', kind: StudyKind.metaAnalysis),
    Study(id: 'bell2023', citation: 'Bell et al. 2023', title: 'Integrating Deloading into Strength and Physique Sports Training Programmes: An International Delphi Consensus Approach.', journal: 'Sports Med Open', doi: '10.1186/s40798-023-00633-0', pmid: '37730925', kind: StudyKind.consensus),
    Study(id: 'mcnulty2020', citation: 'McNulty et al. 2020', title: 'The Effects of Menstrual Cycle Phase on Exercise Performance in Eumenorrheic Women: A Systematic Review and Meta-Analysis.', journal: 'Sports Med', doi: '10.1007/s40279-020-01319-3', pmid: '32661839', kind: StudyKind.metaAnalysis),
    Study(id: 'elliottsale2020', citation: 'Elliott-Sale et al. 2020', title: 'The Effects of Oral Contraceptives on Exercise Performance in Women: A Systematic Review and Meta-analysis.', journal: 'Sports Med', doi: '10.1007/s40279-020-01317-5', pmid: '32666247', kind: StudyKind.metaAnalysis),
    Study(id: 'windred2024', citation: 'Windred et al. 2024', title: 'Sleep regularity is a stronger predictor of mortality risk than sleep duration: A prospective cohort study.', journal: 'Sleep', doi: '10.1093/sleep/zsad253', pmid: '37738616', kind: StudyKind.cohort),
    Study(id: 'patel2017', citation: 'Patel et al. 2017', title: 'Effect of a Game-Based Intervention Designed to Enhance Social Incentives to Increase Physical Activity Among Families: The BE FIT Randomized Clinical Trial.', journal: 'JAMA Intern Med', doi: '10.1001/jamainternmed.2017.3458', pmid: '28973115', kind: StudyKind.trial),
    Study(id: 'patel2019', citation: 'Patel et al. 2019', title: 'Effectiveness of Behaviorally Designed Gamification Interventions With Social Incentives for Increasing Physical Activity Among Overweight and Obese Adults Across the United States: The STEP UP Randomized Clinical Trial.', journal: 'JAMA Intern Med', doi: '10.1001/jamainternmed.2019.3505', pmid: '31498375', kind: StudyKind.trial),
    Study(id: 'mazeas2022', citation: 'Mazeas et al. 2022', title: 'Evaluating the Effectiveness of Gamification on Physical Activity: Systematic Review and Meta-analysis of Randomized Controlled Trials.', journal: 'J Med Internet Res', doi: '10.2196/26779', pmid: '34982715', kind: StudyKind.metaAnalysis),
    Study(id: 'hall2011', citation: 'Hall et al. 2011', title: 'Quantification of the effect of energy imbalance on bodyweight.', journal: 'Lancet', doi: '10.1016/S0140-6736(11)60812-X', pmid: '21872751', kind: StudyKind.study),
    Study(id: 'steinberg2013', citation: 'Steinberg et al. 2013', title: 'The efficacy of a daily self-weighing weight loss intervention using smart scales and e-mail.', journal: 'Obesity (Silver Spring)', doi: '10.1002/oby.20396', pmid: '23512320', kind: StudyKind.trial),
    Study(id: 'steinberg2015', citation: 'Steinberg et al. 2015', title: 'Weighing every day matters: daily weighing improves weight loss and adoption of weight control behaviors.', journal: 'J Acad Nutr Diet', doi: '10.1016/j.jand.2014.12.011', pmid: '25683820', kind: StudyKind.study),
    Study(id: 'helms2016', citation: 'Helms et al. 2016', title: 'Application of the Repetitions in Reserve-Based Rating of Perceived Exertion Scale for Resistance Training.', journal: 'Strength Cond J', doi: '10.1519/SSC.0000000000000218', pmid: '27531969', kind: StudyKind.review),
    Study(id: 'zourdos2016', citation: 'Zourdos et al. 2016', title: 'Novel Resistance Training-Specific Rating of Perceived Exertion Scale Measuring Repetitions in Reserve.', journal: 'J Strength Cond Res', doi: '10.1519/JSC.0000000000001049', pmid: '26049792', kind: StudyKind.study),
    Study(id: 'robinson2024', citation: 'Robinson et al. 2024', title: 'Exploring the Dose-Response Relationship Between Estimated Resistance Training Proximity to Failure, Strength Gain, and Muscle Hypertrophy: A Series of Meta-Regressions.', journal: 'Sports Med', doi: '10.1007/s40279-024-02069-2', pmid: '38970765', kind: StudyKind.metaAnalysis),
    Study(id: 'refalo2023', citation: 'Refalo et al. 2023', title: 'Influence of Resistance Training Proximity-to-Failure on Skeletal Muscle Hypertrophy: A Systematic Review with Meta-analysis.', journal: 'Sports Med', doi: '10.1007/s40279-022-01784-y', pmid: '36334240', kind: StudyKind.metaAnalysis),
    Study(id: 'schoenfeld2016freq', citation: 'Schoenfeld et al. 2016', title: 'Effects of Resistance Training Frequency on Measures of Muscle Hypertrophy: A Systematic Review and Meta-Analysis.', journal: 'Sports Med', doi: '10.1007/s40279-016-0543-8', pmid: '27102172', kind: StudyKind.metaAnalysis),
    Study(id: 'schoenfeld2017load', citation: 'Schoenfeld et al. 2017', title: 'Strength and Hypertrophy Adaptations Between Low- vs. High-Load Resistance Training: A Systematic Review and Meta-analysis.', journal: 'J Strength Cond Res', doi: '10.1519/JSC.0000000000002200', pmid: '28834797', kind: StudyKind.metaAnalysis),
    Study(id: 'konrad2023', citation: 'Konrad et al. 2023', title: 'Chronic effects of stretching on range of motion with consideration of potential moderating variables: A systematic review with meta-analysis.', journal: 'J Sport Health Sci', doi: '10.1016/j.jshs.2023.06.002', pmid: '37301370', kind: StudyKind.metaAnalysis),
    Study(id: 'afonso2021', citation: 'Afonso et al. 2021', title: 'Strength Training versus Stretching for Improving Range of Motion: A Systematic Review and Meta-Analysis.', journal: 'Healthcare (Basel)', doi: '10.3390/healthcare9040427', pmid: '33917036', kind: StudyKind.metaAnalysis),
    Study(id: 'behm2016', citation: 'Behm et al. 2016', title: 'Acute effects of muscle stretching on physical performance, range of motion, and injury incidence in healthy active individuals: a systematic review.', journal: 'Appl Physiol Nutr Metab', doi: '10.1139/apnm-2015-0235', pmid: '26642915', kind: StudyKind.systematicReview),
    Study(id: 'bennell1998', citation: 'Bennell et al. 1998', title: 'Intra-rater and inter-rater reliability of a weight-bearing lunge measure of ankle dorsiflexion.', journal: 'Aust J Physiother', doi: '10.1016/S0004-9514(14)60377-9', pmid: '11676731', kind: StudyKind.study),
  ];

  static const List<EvidenceRule> rules = [
    EvidenceRule(id: 'recovery.hrv', title: 'HRV im Wochenmittel', statement: 'Maßgeblich für die Tagesform ist der 7-Tage-Schnitt der HRV relativ zur persönlichen Baseline, nicht die einzelne Nacht.', strength: EvidenceStrength.moderate, studyIDs: ['plews2012', 'plews2013', 'buchheit2014']),
    EvidenceRule(id: 'recovery.rhr', title: 'Ruhepuls', statement: 'Ein Ruhepuls deutlich über dem eigenen Mittel kann auf unvollständige Erholung hinweisen; die Schwelle von +5 Schlägen ist ein vorsichtiger Praxiswert.', strength: EvidenceStrength.practice, studyIDs: ['buchheit2014']),
    EvidenceRule(id: 'recovery.sleep', title: 'Schlafdauer', statement: 'Erwachsene brauchen regelmäßig mindestens 7 Stunden Schlaf; Schlafmangel verschlechtert Ausdauerleistung und Erholung.', strength: EvidenceStrength.strong, studyIDs: ['watson2015', 'fullagar2015', 'walsh2021']),
    EvidenceRule(id: 'recovery.subjective', title: 'Befinden zählt', statement: 'Subjektives Befinden reagiert empfindlicher auf Trainingsbelastung als viele objektive Marker und gehört in die Einordnung.', strength: EvidenceStrength.strong, studyIDs: ['saw2016']),
    EvidenceRule(id: 'sleep.regularity', title: 'Regelmäßiger Schlaf', statement: 'Regelmäßige Schlafzeiten sagen Gesundheit stärker voraus als die Schlafdauer allein.', strength: EvidenceStrength.moderate, studyIDs: ['windred2024', 'walsh2021']),
    EvidenceRule(id: 'load.rpe', title: 'Belastung per RPE', statement: 'Das subjektive Anstrengungsempfinden je Einheit (Session-RPE) ist ein gültiges Maß für die Trainingsbelastung über Sportarten hinweg.', strength: EvidenceStrength.moderate, studyIDs: ['foster2001']),
    EvidenceRule(id: 'intensity.distribution', title: 'Überwiegend locker', statement: 'Ausdauersportler trainieren erfolgreich mit etwa 80 % lockerer Intensität und wenigen harten Einheiten; polarisierte und pyramidale Verteilungen sind ähnlich wirksam.', strength: EvidenceStrength.strong, studyIDs: ['seiler2006', 'esteveLanao2007', 'munoz2014', 'rosenblat2025']),
    EvidenceRule(id: 'run.4x4', title: '4×4-Intervalle', statement: '4×4 Minuten bei 90–95 % der maximalen Herzfrequenz mit 3 Minuten Trabpause steigern die VO2max stärker als moderates Dauertraining gleicher Arbeit.', strength: EvidenceStrength.moderate, studyIDs: ['helgerud2007']),
    EvidenceRule(id: 'run.decoupling', title: 'Aerobe Kopplung', statement: 'Bei langer, gleichmäßiger Belastung steigt die Herzfrequenz relativ zur Leistung (Herz-Kreislauf-Drift); wie spät und wie stark das geschieht, beschreibt die Ausdauer-Robustheit. Die Grenze von 5 % ist ein Praxiswert.', strength: EvidenceStrength.practice, studyIDs: ['coyle2001', 'maunder2021']),
    EvidenceRule(id: 'run.pace-check', title: 'Pace-Check', statement: 'Die Schwelle wird an der Schwellen-HF verankert; 4×4-Intervalle zielen auf 90–95 % HFmax. Der Abgleich mit Trainingsläufen ist eine vorsichtige Praxisregel, der Feldtest bleibt maßgeblich.', strength: EvidenceStrength.practice, studyIDs: ['helgerud2007', 'esteveLanao2007', 'seiler2006']),
    EvidenceRule(id: 'hr.threshold-zones', title: 'Zonen an der Schwelle', statement: 'Intensitätszonen werden besser an Schwellen als an Prozent der maximalen Herzfrequenz verankert; die Zonenbreiten nach Friel sind Praxiswerte.', strength: EvidenceStrength.moderate, studyIDs: ['esteveLanao2007', 'seiler2006']),
    EvidenceRule(id: 'hr.max-formula', title: 'Keine HFmax-Formel', statement: 'Altersformeln für die maximale Herzfrequenz weichen im Einzelfall um rund 10 Schläge ab; gemessene Werte sind besser.', strength: EvidenceStrength.strong, studyIDs: ['nes2013']),
    EvidenceRule(id: 'hr.optical', title: 'Optischer Puls', statement: 'Optische Pulsmesser am Handgelenk unterschätzen die Zeit in hohen Intensitätszonen.', strength: EvidenceStrength.moderate, studyIDs: ['neudorfer2024']),
    EvidenceRule(id: 'strength.economy', title: 'Kraft für Ausdauer', statement: 'Schweres Krafttraining zwei- bis dreimal pro Woche verbessert Lauf- und Radökonomie, ohne Ausdauerwerte zu verschlechtern.', strength: EvidenceStrength.strong, studyIDs: ['ronnestad2013', 'denadai2017', 'blagrove2018']),
    EvidenceRule(id: 'strength.interference', title: 'Interferenz ist klein', statement: 'Ausdauer- und Krafttraining kombiniert bremst vor allem die Beinkraft etwas; bei trainierten Ausdauersportlern ist der VO2max-Nachteil gering.', strength: EvidenceStrength.strong, studyIDs: ['wilson2012', 'murlasits2017', 'huiberts2023']),
    EvidenceRule(id: 'gym.progression', title: 'Progression', statement: 'Steigt das Ziel bei den Wiederholungen um 1–2, wird die Last um 2–10 % erhöht (Doppelprogression).', strength: EvidenceStrength.strong, studyIDs: ['acsm2009', 'currier2026']),
    EvidenceRule(id: 'gym.volume', title: 'Sätze pro Woche', statement: 'Mehr wöchentliche Sätze je Muskel bringen mehr Muskelzuwachs, mit abnehmendem Ertrag; für Kraft genügen schon wenige Sätze an zwei Tagen pro Woche.', strength: EvidenceStrength.strong, studyIDs: ['schoenfeld2017', 'pelland2025', 'currier2026']),
    EvidenceRule(id: 'swim.css', title: 'CSS-Test', statement: 'Die kritische Schwimmgeschwindigkeit aus zwei Maximalstrecken (400 m und 200 m) schätzt das Tempo, das lange ohne Erschöpfung gehalten werden kann.', strength: EvidenceStrength.moderate, studyIDs: ['wakayoshi1992']),
    EvidenceRule(id: 'activity.who', title: 'Mindestens aktiv bleiben', statement: 'Erwachsene sollten pro Woche 150–300 Minuten moderat oder 75–150 Minuten intensiv aktiv sein und regelmäßig Muskeln kräftigen; für Schwangere, nach der Geburt und bei chronischen Erkrankungen gelten eigene Empfehlungen.', strength: EvidenceStrength.strong, studyIDs: ['bull2020']),
    EvidenceRule(id: 'weightloss.rate', title: 'Tempo beim Abnehmen', statement: 'Langsames Abnehmen (etwa 0,7 % des Körpergewichts pro Woche) bewahrte in einer Studie mit Leistungssportlern mehr Muskelmasse und Kraft als schnelles (1,4 %). Nach einem Jahr waren die Werte gleich; empfohlen werden 0,5–1 kg pro Woche.', strength: EvidenceStrength.moderate, studyIDs: ['garthe2011']),
    EvidenceRule(id: 'weightloss.exercise', title: 'Sport und Abnehmen', statement: 'Mit 150–250 Minuten moderatem Training pro Woche nimmt man nur bescheiden ab (etwa 2 kg); die Ernährung ist der Haupthebel. Krafttraining erhöht nicht den Gewichtsverlust, kann aber die fettfreie Masse erhalten.', strength: EvidenceStrength.strong, studyIDs: ['donnelly2009', 'swift2014']),
    EvidenceRule(id: 'weightloss.protein', title: 'Protein im Defizit', statement: 'Im Kaloriendefizit und beim Krafttraining erhält mehr Protein als die empfohlene Mindestmenge Magermasse; für den Aufbau bringt es über etwa 1,6 g pro kg und Tag nicht mehr.', strength: EvidenceStrength.strong, studyIDs: ['hudson2020', 'morton2018']),
    EvidenceRule(id: 'weightloss.sleep', title: 'Schlaf beim Abnehmen', statement: 'In einer kleinen Crossover-Studie mit Diät sank der Fettanteil am Gewichtsverlust um 55 %, wenn die Schlafgelegenheit 5,5 statt 8,5 Stunden betrug.', strength: EvidenceStrength.moderate, studyIDs: ['nedeltcheva2010', 'watson2015']),
    EvidenceRule(id: 'gain.surplus', title: 'Zunehmen und Muskelaufbau', statement: 'Üblich sind 300–500 kcal Überschuss pro Tag mit konsequentem Krafttraining; die oft genannten 0,45 kg Zunahme pro Woche, überwiegend als Muskeln, sind für viele schwer erreichbar.', strength: EvidenceStrength.practice, studyIDs: ['larsonmeyer2022']),
    EvidenceRule(id: 'run.progression', title: 'Laufumfang steigern', statement: 'Die 10-%-Regel verhinderte in einer randomisierten Studie mit 532 Einsteigern keine Verletzungen (20,8 % gegenüber 20,3 %). Eine Kohortenstudie sah bei mehr als 30 % Steigerung tendenziell mehr entfernungsbedingte Verletzungen. In einer Kohorte mit 5.205 Läuferinnen und Läufern stieg das Verletzungsrisiko, wenn ein einzelner Lauf mehr als 10 % über dem längsten der letzten 30 Tage lag (Hazard Ratio 1,64). Die App steigert daher vorsichtig, nie über 30 %, und begrenzt einzelne Läufe.', strength: EvidenceStrength.practice, studyIDs: ['buist2007', 'nielsen2014', 'frandsen2025']),
    EvidenceRule(id: 'run.minimum', title: 'Schon wenig Laufen hilft', statement: 'Laufen ist mit 27 % niedrigerem Sterberisiko verbunden, unabhängig von Häufigkeit, Dauer und Tempo; selbst einmal pro Woche ist besser als gar nicht.', strength: EvidenceStrength.moderate, studyIDs: ['pedisic2019']),
    EvidenceRule(id: 'rhr.endurance', title: 'Ruhepuls senken', statement: 'Ausdauertraining senkt den Ruhepuls; bei Untrainierten sank er nach einem Jahr Laufen um etwa 7 Schläge pro Minute, bei höherem Ausgangswert und jüngeren Menschen stärker.', strength: EvidenceStrength.strong, studyIDs: ['hespanhol2015', 'reimers2018']),
    EvidenceRule(id: 'weight.trend', title: 'Gewichtsverlauf statt Formel', statement: 'Der Körper reagiert verzögert auf eine geänderte Energiezufuhr; feste Faustregeln wie 7.700 kcal je kg überschätzen die Abnahme auf Dauer. Deshalb vergleicht die App den gemessenen Verlauf mit dem Plan und passt in kleinen Schritten an. Tägliches Wiegen half in einer randomisierten Studie beim Abnehmen.', strength: EvidenceStrength.moderate, studyIDs: ['hall2011', 'steinberg2013', 'steinberg2015']),
    EvidenceRule(id: 'gym.rir', title: 'Wiederholungen in Reserve', statement: 'Wie viele Wiederholungen noch gegangen wären (RIR), lässt sich gut schätzen und eignet sich zum Steuern der Last. Für Muskelaufbau sollten Sätze nah am Muskelversagen enden; ganz bis zum Versagen bringt kaum mehr. Für Kraft spielt die Nähe zum Versagen kaum eine Rolle.', strength: EvidenceStrength.moderate, studyIDs: ['helms2016', 'zourdos2016', 'robinson2024', 'refalo2023']),
    EvidenceRule(id: 'gym.frequency', title: 'Zweimal pro Woche', statement: 'Jeden großen Muskel mindestens zweimal pro Woche zu trainieren, brachte bei gleichem Umfang mehr Muskelzuwachs als einmal pro Woche.', strength: EvidenceStrength.strong, studyIDs: ['schoenfeld2016freq', 'pelland2025']),
    EvidenceRule(id: 'gym.load', title: 'Leicht oder schwer', statement: 'Muskeln wachsen mit leichten und schweren Gewichten ähnlich, wenn die Sätze anstrengend sind; maximale Kraft steigt mit schweren Gewichten stärker.', strength: EvidenceStrength.strong, studyIDs: ['schoenfeld2017load']),
    EvidenceRule(id: 'motivation.gamification', title: 'Punkte und Rangliste', statement: 'Punkte und Stufen für erreichte eigene Ziele steigerten die Bewegung in Studien (kleiner bis mittlerer Effekt), auch in Familien und mit Wettbewerb zwischen Teilnehmenden. Nach Ende des Spiels ließ der Effekt nach. Die App vergibt Punkte nur für die Einheiten deines Plans, nicht für zusätzliches Training.', strength: EvidenceStrength.moderate, studyIDs: ['mazeas2022', 'patel2017', 'patel2019']),
    EvidenceRule(id: 'fitness.hiit', title: 'Intervalle für die Fitness', statement: 'Intervalltraining steigerte die maximale Sauerstoffaufnahme etwas stärker als Dauertraining (im Mittel +1,2 ml/kg/min), besonders bei geringer Ausgangsfitness.', strength: EvidenceStrength.moderate, studyIDs: ['milanovic2015']),
    EvidenceRule(id: 'plan.deload', title: 'Entlastungswochen', statement: 'Fachleute definieren Deloading als Phase reduzierter Belastung zur Erholung. Wie oft und wie stark ist nicht belegt; die App plant etwa alle vier Wochen eine leichtere Woche als Praxiswert.', strength: EvidenceStrength.practice, studyIDs: ['bell2023']),
    EvidenceRule(id: 'cycle.individual', title: 'Zyklus und Training', statement: 'Die Leistung ist in der frühen Follikelphase im Mittel nur unbedeutend geringer (Effekt −0,06), die Studienqualität niedrig. Allgemeine Regeln lassen sich nicht ableiten; auch für die Pille gibt es keine allgemeine Empfehlung. Deshalb passt die App den Plan nicht nach Zyklusphase an, sondern nach deinem Befinden.', strength: EvidenceStrength.moderate, studyIDs: ['mcnulty2020', 'elliottsale2020']),
    EvidenceRule(id: 'taper', title: 'Tapering', statement: 'Vor dem Wettkampf den Umfang über bis zu drei Wochen um etwa 41–60 % senken, Intensität und Häufigkeit beibehalten.', strength: EvidenceStrength.strong, studyIDs: ['wang2023']),
    EvidenceRule(id: 'energy.measured', title: 'Verbrauch aus Gewicht und Ernährung', statement: 'Der tatsächliche Verbrauch lässt sich aus der Zufuhr und der Änderung der Körperreserven berechnen; mit Gewichtsdaten lag das in Studien nah an der tatsächlichen Zufuhr. Selbst erfasste Mahlzeiten unterschätzen die Zufuhr aber oft deutlich, deshalb zählt die App unvollständige Tage nicht und verwirft unplausible Ergebnisse.', strength: EvidenceStrength.moderate, studyIDs: ['gilmore2014', 'sanghvi2015', 'lichtman1992', 'hall2011']),
    EvidenceRule(id: 'load.fitness-form', title: 'Fitness, Ermüdung, Form', statement: 'Das Impulse-Response-Modell nach Banister beschreibt, wie Training kurzfristig ermüdet und langfristig fitter macht; die App bildet das mit gleitenden Mittelwerten über 7 und 42 Tage ab. Als Vorhersage von Verletzungen taugen solche Belastungsverhältnisse nicht, deshalb warnt die App damit nicht. Liegt die Ermüdung sehr weit über der Fitness (Form unter −30 %, Praxiswert), rät die Tagesampel vorsichtshalber zu lockerem Training, nie zu einer Pause.', strength: EvidenceStrength.practice, studyIDs: ['clarke2013', 'impellizzeri2020']),
    EvidenceRule(id: 'gym.muscle-load', title: 'Muskelbelastung aus Sätzen', statement: 'Für Muskelaufbau zählt die Zahl der anstrengenden Sätze je Muskel und Woche, nicht der Kalorienverbrauch. Mitarbeitende Muskeln (etwa der Trizeps beim Bankdrücken) bekommen einen halben Satz; so beschrieb eine große Meta-Regression die Dosis-Wirkung am besten. Wie lange ein Muskel zur Erholung braucht, ist individuell: Die 48 Stunden der App sind ein vorsichtiger Praxiswert, keine Messung.', strength: EvidenceStrength.practice, studyIDs: ['pelland2025', 'schoenfeld2017']),
    EvidenceRule(id: 'mobility.stretching', title: 'Beweglichkeit trainieren', statement: 'Regelmäßiges Dehnen vergrößert den Bewegungsumfang mit mittlerem Effekt; Halten (statisch) wirkte langfristig stärker als schwunghaftes Dehnen, Dauer und Häufigkeit spielten kaum eine Rolle. Krafttraining über den vollen Bewegungsumfang verbesserte die Beweglichkeit ähnlich gut. Direkt vor Belastung mindert langes Halten (ab etwa 60 s je Muskel) die Leistung leicht; deshalb vor dem Training nur dynamische Übungen. Verletzungen verhindert Dehnen nach bisheriger Datenlage nicht sicher.', strength: EvidenceStrength.strong, studyIDs: ['konrad2023', 'afonso2021', 'behm2016']),
    EvidenceRule(id: 'mobility.focus', title: 'Schwerpunkte der Mobility-Einheit', statement: 'Die App wählt die Körperregionen nach den Sätzen der letzten 48 Stunden, den Ausdauerminuten seit gestern und den eigenen Testergebnissen. Die Zuordnung von Muskeln und Sportarten zu Regionen und die Grenzen der Selbsttests sind Praxiswerte zur Orientierung, keine Diagnose. Der Knie-zur-Wand-Test ist gut wiederholbar (Bennell et al. 1998) und eignet sich deshalb, Veränderungen über Wochen zu verfolgen.', strength: EvidenceStrength.practice, studyIDs: ['bennell1998', 'konrad2023']),
    EvidenceRule(id: 'load.weekly', title: 'Wochenbelastung', statement: 'Die App summiert die Belastung aller Sportarten (Wert der Uhr, sonst Dauer × Intensität bzw. Anstrengung) und vergleicht die letzten 7 Tage mit dem Schnitt der drei Wochen davor. Ab 30 % mehr rät sie, die nächsten Tage locker zu planen. Die Grenze stammt aus einer Laufstudie und ist für andere Sportarten ein Praxiswert; als Verletzungsvorhersage ist so ein Verhältnis nicht belegt.', strength: EvidenceStrength.practice, studyIDs: ['foster2001', 'nielsen2014', 'impellizzeri2020']),
    EvidenceRule(id: 'sleep.extension', title: 'Mehr Schlaf für mehr Leistung', statement: 'Basketballer, die über mehrere Wochen etwa zwei Stunden länger schliefen, sprinteten schneller, trafen besser und waren wacher. Die App plant nach kurzen Nächten etwas mehr Schlaf ein; wie viel genau, ist ein Praxiswert.', strength: EvidenceStrength.moderate, studyIDs: ['mah2011']),
    EvidenceRule(id: 'nutrition.energy', title: 'Energiebedarf', statement: 'Der Grundumsatz wird mit der Mifflin-St-Jeor-Formel geschätzt; der Tagesbedarf ergibt sich aus Alltag und Training. Geplante, noch nicht aufgezeichnete Einheiten schätzt die App über MET-Werte; die Makros richten sich nach dieser Energie, Fett bleibt bei mindestens 20 %.', strength: EvidenceStrength.moderate, studyIDs: ['mifflin1990', 'thomas2016', 'ainsworth2011']),
    EvidenceRule(id: 'nutrition.carbs', title: 'Kohlenhydrate nach Belastung', statement: 'Der Kohlenhydratbedarf richtet sich nach der Trainingsbelastung des Tages (etwa 3 bis 10 g pro kg Körpergewicht).', strength: EvidenceStrength.strong, studyIDs: ['thomas2016']),
    EvidenceRule(id: 'nutrition.protein', title: 'Protein', statement: '1,4–2,0 g Protein pro kg Körpergewicht und Tag, verteilt auf Portionen von etwa 0,25 g/kg alle 3–4 Stunden.', strength: EvidenceStrength.strong, studyIDs: ['jaeger2017', 'thomas2016']),
    EvidenceRule(id: 'nutrition.reds', title: 'Genug Energie', statement: 'Dauerhaft zu wenig Energie im Verhältnis zum Training schadet Gesundheit und Leistung; eine Untergrenze schützt davor.', strength: EvidenceStrength.strong, studyIDs: ['mountjoy2023']),
  ];
  // dart format on

  static final Map<String, Study> studiesByID = {for (final study in studies) study.id: study};

  static final Map<String, EvidenceRule> rulesByID = {for (final rule in rules) rule.id: rule};

  static List<EvidenceRule> rulesFor(List<String> ids) => [for (final id in ids) ?rulesByID[id]];
}

/// Regeln hinter der Tagesampel.
extension RecommendationEvidence on Recommendation {
  List<String> get evidenceIDs => [
    'recovery.hrv',
    'recovery.rhr',
    'recovery.sleep',
    'recovery.subjective',
    if (isLimitedByForm) 'load.fitness-form',
  ];
}
