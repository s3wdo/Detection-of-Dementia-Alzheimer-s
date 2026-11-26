import '../../features/counselling/data/models/counselling_models.dart';

// Educational articles used by the counselling prototype. General information
// only, written in plain language; each names the organisation whose public
// guidance it summarises. The clinical team should review them before real use.

const counsellingResources = [
  Resource(
    slug: 'understanding-your-results',
    title: 'Understanding your MRI analysis',
    category: ResourceCategory.results,
    minutes: 4,
    source: 'NeuroSense clinical team (project content)',
    keywords: ['result', 'analysis', 'confidence', 'ai', 'model', 'classification', 'demented', 'report'],
    summary:
        'What the AI-assisted analysis is, what it cannot tell you, and why your doctor reviews every result.',
    sections: [
      (
        heading: 'What the analysis does',
        body: 'A computer model looks at one image from your MRI scan and sorts it into one of four groups: '
            "Cognitively Normal, Early MCI, Late MCI or Alzheimer's Disease. MCI means mild cognitive impairment: "
            'changes in memory or thinking that are noticeable but do not stop a person managing daily life. '
            'The model was trained on a research dataset. It does not examine you and does not know your history.',
      ),
      (
        heading: 'What the result is not',
        body: 'The group the model chose is not a diagnosis and not the chance that you have a condition. '
            'The model can be wrong, which is why a doctor checks every result.',
      ),
      (
        heading: 'Why your doctor reviews it',
        body: 'The analysis is a support tool, not a diagnosis. Your doctor looks at it together with your '
            'examination, history and other tests, and records their own decision. You only see results after '
            'that review.',
      ),
    ],
  ),
  Resource(
    slug: 'what-is-dementia',
    title: "Dementia and Alzheimer's disease",
    category: ResourceCategory.condition,
    minutes: 5,
    source: 'World Health Organization; National Institute on Aging',
    keywords: ['dementia', 'alzheimer', 'memory', 'symptom', 'stage', 'forget'],
    summary:
        "Dementia is a general term for problems with memory and thinking. Alzheimer's disease is its most common cause.",
    sections: [
      (
        heading: 'What dementia is',
        body: 'Dementia describes a group of symptoms that affect memory, thinking and the ability to manage '
            'everyday life. It is not a normal part of ageing.',
      ),
      (
        heading: "Alzheimer's disease",
        body: "Alzheimer's disease is the most common cause of dementia. Other causes include vascular disease "
            'and Lewy body disease. Symptoms often start gradually and change over time, differently for each person.',
      ),
      (
        heading: 'How it is diagnosed',
        body: 'Diagnosis is made by a doctor using a combination of history, examination, memory and thinking '
            'tests, blood tests and sometimes brain scans. No single test decides it on its own.',
      ),
    ],
  ),
  Resource(
    slug: 'mri-explained',
    title: 'What an MRI scan shows',
    category: ResourceCategory.results,
    minutes: 3,
    source: 'RadiologyInfo.org (ACR & RSNA); National Institute on Aging',
    keywords: ['mri', 'scan', 'image', 'brain scan', 'magnet'],
    summary: 'How MRI makes pictures of the brain and how doctors use them when assessing memory problems.',
    sections: [
      (
        heading: 'How MRI works',
        body: 'MRI uses a strong magnet and radio waves — not X-rays — to make detailed pictures of the brain.',
      ),
      (
        heading: 'Why it is used',
        body: 'Brain MRI can show changes in brain structure and can help rule out other causes of symptoms, such as '
            'a stroke or a tumour. It is one part of an assessment, interpreted together with other information.',
      ),
    ],
  ),
  Resource(
    slug: 'preparing-appointment',
    title: 'Preparing for your appointment',
    category: ResourceCategory.appointments,
    minutes: 3,
    source: "Alzheimer's Association",
    keywords: ['appointment', 'visit', 'prepare', 'bring', 'consultation'],
    summary: 'A short checklist to help you get the most from your visit.',
    sections: [
      (
        heading: 'What to bring',
        body: 'A list of all medicines you take (including vitamins), any previous test results, and notes about '
            'changes you or your family have noticed and when they started.',
      ),
      (
        heading: 'Bring someone with you',
        body: 'A family member or friend can help you remember what was said and can share what they have noticed.',
      ),
    ],
  ),
  Resource(
    slug: 'questions-for-doctor',
    title: 'Questions to ask your doctor',
    category: ResourceCategory.appointments,
    minutes: 2,
    source: 'National Institute on Aging',
    keywords: ['question', 'ask', 'doctor', 'what should i ask'],
    summary: 'Questions many people find helpful to ask about their results and next steps.',
    sections: [
      (
        heading: 'About your results',
        body: '• What did my tests and scan show?\n• How sure are you, and do I need more tests?\n'
            '• How does the AI analysis fit with your own assessment?',
      ),
      (
        heading: 'About next steps',
        body: '• What happens next, and when should I come back?\n• Are there services or support groups for me '
            'and my family?\n• Who can I contact if I have questions later?',
      ),
    ],
  ),
  Resource(
    slug: 'supporting-family',
    title: 'Supporting a family member',
    category: ResourceCategory.caregiving,
    minutes: 4,
    source: "Alzheimer's Association; NHS",
    keywords: ['family', 'carer', 'caregiver', 'support', 'mother', 'father', 'husband', 'wife', 'parent'],
    summary: 'Everyday ways to help someone with memory problems — and to look after yourself too.',
    sections: [
      (
        heading: 'Communicating',
        body: 'Speak calmly, one idea at a time, and give the person time to answer. Avoid arguing about mistakes.',
      ),
      (
        heading: 'Routines',
        body: 'Regular routines, calendars and labels can make daily life easier and reduce worry.',
      ),
      (
        heading: 'Looking after yourself',
        body: 'Caring can be tiring. Ask for help, take breaks, and look for local carer support groups.',
      ),
    ],
  ),
  Resource(
    slug: 'brain-health',
    title: 'Lifestyle and brain health',
    category: ResourceCategory.lifestyle,
    minutes: 4,
    source: 'World Health Organization — risk reduction guidelines',
    keywords: ['lifestyle', 'exercise', 'diet', 'sleep', 'healthy', 'prevent', 'activity', 'brain health'],
    summary: 'General habits that support brain and heart health. They help many people but are not a guarantee.',
    sections: [
      (
        heading: 'Stay active',
        body: 'Regular physical activity that suits you, such as walking, is good for the heart and the brain.',
      ),
      (
        heading: 'Stay connected',
        body: 'Time with family and friends, hobbies and learning new things keep the mind engaged.',
      ),
      (
        heading: 'Look after your health',
        body: 'Keep check-ups for blood pressure, blood sugar and hearing, avoid smoking and limit alcohol. '
            'Talk to your doctor before making big changes.',
      ),
    ],
  ),
  Resource(
    slug: 'memory-aids',
    title: 'Everyday memory aids',
    category: ResourceCategory.lifestyle,
    minutes: 2,
    source: 'NHS',
    keywords: ['remember', 'memory aid', 'reminder', 'forgetting', 'calendar'],
    summary: 'Simple tools that make day-to-day life easier.',
    sections: [
      (
        heading: 'Ideas that help',
        body: '• A large calendar or whiteboard for appointments\n• Phone reminders and alarms\n'
            '• A fixed place for keys, glasses and wallet\n• Labels on cupboards and drawers',
      ),
    ],
  ),
];
