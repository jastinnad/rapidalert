// Preparedness assistant content, copied word for word from the website's
// guided chatbot (public/js/chatbot.js: hazardCards, hazardResponses,
// infoContent) so mobile and web give identical advice. Bundled in the app so
// it still works with no connection. Keep in sync with chatbot.js.

enum HazardTone { blue, orange, violet, brown, slate }

class HazardCard {
  const HazardCard({required this.key, required this.label, required this.icon, required this.tone});

  final String key;
  final String label;
  final String icon;
  final HazardTone tone;
}

class PreparednessFollowUp {
  const PreparednessFollowUp({required this.label, required this.infoKey});

  final String label;
  final String infoKey;
}

class HazardResponse {
  const HazardResponse({required this.title, required this.body, required this.followUps});

  final String title;
  final String body;
  final List<PreparednessFollowUp> followUps;
}

const preparednessGreeting =
    'I can help with multi-hazard preparedness. Choose a hazard below to see the safest next steps.';

const hazardCards = [
  HazardCard(key: 'flood', label: 'Flood', icon: '🌊', tone: HazardTone.blue),
  HazardCard(key: 'earthquake', label: 'Earthquake', icon: '🏚️', tone: HazardTone.orange),
  HazardCard(key: 'typhoon', label: 'Typhoon', icon: '🌀', tone: HazardTone.violet),
  HazardCard(key: 'landslide', label: 'Landslide', icon: '⛰️', tone: HazardTone.brown),
  HazardCard(key: 'gobag', label: 'Go-bag', icon: '🎒', tone: HazardTone.slate),
  HazardCard(key: 'other', label: 'Other', icon: '⚠️', tone: HazardTone.slate),
];

const hazardResponses = <String, HazardResponse>{
  'flood': HazardResponse(
    title: 'Flood readiness',
    body: 'Move to higher ground, secure documents, and keep your go-bag ready. Avoid walking or driving through floodwater.',
    followUps: [
      PreparednessFollowUp(label: 'Before Flood', infoKey: 'flood_before'),
      PreparednessFollowUp(label: 'During Flood', infoKey: 'flood_during'),
      PreparednessFollowUp(label: 'After Flood', infoKey: 'flood_after'),
    ],
  ),
  'earthquake': HazardResponse(
    title: 'Earthquake readiness',
    body: 'Drop, Cover, and Hold On. Keep clear exit paths and secure heavy items that could fall.',
    followUps: [
      PreparednessFollowUp(label: 'Before Earthquake', infoKey: 'earthquake_before'),
      PreparednessFollowUp(label: 'During Earthquake', infoKey: 'earthquake_during'),
      PreparednessFollowUp(label: 'After Earthquake', infoKey: 'earthquake_after'),
    ],
  ),
  'typhoon': HazardResponse(
    title: 'Typhoon readiness',
    body: 'Charge devices early, secure loose outdoor items, and prepare clean water, food, and medicines.',
    followUps: [
      PreparednessFollowUp(label: 'Before Typhoon', infoKey: 'typhoon_before'),
      PreparednessFollowUp(label: 'During Typhoon', infoKey: 'typhoon_during'),
      PreparednessFollowUp(label: 'After Typhoon', infoKey: 'typhoon_after'),
    ],
  ),
  'landslide': HazardResponse(
    title: 'Landslide safety',
    body: 'Watch for cracks, leaning trees, and rumbling sounds. Move away from slopes and stay alert after heavy rainfall.',
    followUps: [
      PreparednessFollowUp(label: 'Warning Signs', infoKey: 'landslide_warning'),
      PreparednessFollowUp(label: 'Prevention', infoKey: 'landslide_prevention'),
      PreparednessFollowUp(label: 'During Landslide', infoKey: 'landslide_during'),
    ],
  ),
  'gobag': HazardResponse(
    title: 'Go-bag essentials',
    body: 'Pack IDs, water, food, medications, flashlight, power bank, and a small amount of cash in a waterproof bag.',
    followUps: [
      PreparednessFollowUp(label: 'Documents', infoKey: 'gobag_documents'),
      PreparednessFollowUp(label: 'Water & Food', infoKey: 'gobag_food'),
      PreparednessFollowUp(label: 'Medical & Hygiene', infoKey: 'gobag_medical'),
      PreparednessFollowUp(label: 'Equipment', infoKey: 'gobag_equipment'),
    ],
  ),
  'other': HazardResponse(
    title: 'General emergency guidance',
    body: 'Stay calm, follow official advisories, keep emergency contacts ready, and help vulnerable neighbors when it is safe to do so.',
    followUps: [
      PreparednessFollowUp(label: 'General Safety', infoKey: 'other_general'),
      PreparednessFollowUp(label: 'Resources', infoKey: 'other_resources'),
      PreparednessFollowUp(label: 'Safety Status', infoKey: 'other_safety'),
    ],
  ),
};

const preparednessInfo = <String, String>{
  'flood_before':
      'Flood Preparation:\n- Move important items, documents, and electronics to higher ground.\n- Prepare your go-bag: water, food, meds, IDs, flashlight, charger, cash.\n- Know your evacuation route and nearest evacuation center.\n- Keep your phone charged and store emergency numbers.\n- Stock supplies for at least 3 days.',
  'flood_during':
      'Stay Safe During Flood:\n- Avoid walking or driving through floodwater, even if shallow.\n- Move to higher ground immediately.\n- Stay indoors if water is outside.\n- Do not touch electrical equipment if wet.\n- Keep your phone charged and stay in contact with family.',
  'flood_after':
      'After the Flood:\n- Check for injuries and provide first aid.\n- Document damage with photos for insurance.\n- Listen to authorities before returning home.\n- Boil water before drinking.\n- Return to your home only when declared safe.',
  'earthquake_before':
      'Earthquake Preparation:\n- Secure heavy furniture to walls.\n- Keep shoes, flashlight, and water near your bed.\n- Practice Drop, Cover, and Hold On with family.\n- Know safe spots in each room.\n- Create a family meeting plan.',
  'earthquake_during':
      'During Earthquake:\n- DROP immediately to hands and knees.\n- COVER your head and neck under a sturdy desk or table.\n- HOLD ON and protect yourself until shaking stops.\n- If outdoors, move away from buildings and power lines.\n- If driving, pull over safely and stay in the vehicle.',
  'earthquake_after':
      'After Earthquake:\n- Check yourself and others for injuries.\n- Inspect for gas leaks, electrical hazards, and structural damage.\n- Be ready for aftershocks.\n- Stay out of damaged buildings.\n- Await official all-clear before returning home.',
  'typhoon_before':
      'Typhoon Preparation:\n- Charge phones, power banks, and battery-powered radios.\n- Stock clean water, food, and medicines for 3-7 days.\n- Secure windows, loose roof items, and outdoor items.\n- Trim branches that could fall.\n- Keep IDs in a waterproof pouch.',
  'typhoon_during':
      'During Typhoon:\n- Stay indoors away from windows.\n- Listen to weather updates and official warnings.\n- Do not go outside or use phones except emergencies.\n- If flooding occurs, evacuate to higher ground.\n- Keep children and elderly with you at all times.',
  'typhoon_after':
      'After Typhoon:\n- Check for hazards: downed lines, fallen trees, contaminated water.\n- Stay out of flooded areas.\n- Document damage for insurance.\n- Boil water before drinking.\n- Avoid using candles; use flashlights instead.',
  'landslide_warning':
      'Warning Signs of Landslide:\n- Cracks in the ground or on slopes.\n- Leaning trees or tilted fence posts.\n- Water seeping from slopes.\n- Unusual sounds like rumbling or cracking.\n- Recent heavy rainfall and soil movement.',
  'landslide_prevention':
      'Reduce Landslide Risk:\n- Avoid building near steep slopes.\n- Plant trees and vegetation on slopes.\n- Maintain proper drainage on hillsides.\n- Remove loose rocks and debris.\n- Consult geotechnical engineers for high-risk areas.',
  'landslide_during':
      'During Landslide:\n- Evacuate immediately away from slope.\n- Move perpendicular to the slide direction.\n- Do not try to outrun a fast-moving slide.\n- Seek shelter on high ground away from slopes.\n- Alert neighbors and call authorities.',
  'gobag_documents':
      'Documents for Go-bag:\n- Birth certificates and IDs (original or certified copies).\n- Passport or travel documents.\n- Marriage certificate.\n- Insurance policies and documents.\n- Deeds and property records.\n- Keep copies in waterproof pouch.',
  'gobag_food':
      'Water & Food for 72 Hours:\n- Minimum 2 liters of drinking water per person.\n- Ready-to-eat foods: biscuits, canned goods, energy bars.\n- Comfort foods for children.\n- Salt and vitamins.\n- Can opener if bringing canned goods.\n- No special refrigeration needed.',
  'gobag_medical':
      'Medical & Hygiene Supplies:\n- Prescription medicines (3-day supply).\n- First aid kit with bandages and antiseptic.\n- Pain reliever and antihistamine.\n- Masks, hand sanitizer, soap.\n- Feminine hygiene products.\n- Denture tablets or dental care items if needed.',
  'gobag_equipment':
      'Equipment for Go-bag:\n- Flashlight with spare batteries.\n- Portable radio or phone charger.\n- Whistle for signaling.\n- Comfortable shoes and extra socks.\n- Light jacket or rain poncho.\n- Small towel and change of clothes.\n- Small amount of cash.\n- This bag should fit in a backpack or small luggage.',
  'other_general':
      'General Emergency Safety:\n- Stay calm and alert during emergencies.\n- Follow official government advisories.\n- Keep your phone charged and have emergency contacts.\n- Know your barangay evacuation center location.\n- Have a family meeting point if separated.\n- Keep important documents in a waterproof bag.\n- Help neighbors and vulnerable people.',
  'other_resources':
      'Emergency Resources Available:\n- Local CDRRMO (Calamity/Disaster Risk Reduction Management Office).\n- Barangay officials and community leaders.\n- Philippine National Red Cross branches.\n- Local health centers for medical assistance.\n- Police and firefighter stations.\n- Community hotlines for emergencies.\n- Social services for vulnerable groups.',
  'other_safety':
      'Maintaining Safety:\n- Avoid flooded or unsafe areas.\n- Do not touch downed electrical lines.\n- Stay away from fire scenes and collapsed structures.\n- Do not drive through disaster zones unless necessary.\n- Report hazards to authorities immediately.\n- Help distribute information to community.\n- Take care of your mental health during crisis.',
};
