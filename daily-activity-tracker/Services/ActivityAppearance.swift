import Foundation

/// Suggests icon and color for activities based on name keywords.
/// Falls back to type/metric-kind defaults when no keyword matches.
enum ActivityAppearance {

    struct Suggestion {
        let icon: String
        let color: String
    }

    // MARK: - Public API

    static func suggest(for name: String, type: ActivityType, metricKind: MetricKind? = nil) -> Suggestion {
        let tokens = name.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }

        // Try keyword match (first hit wins, ordered by specificity)
        for token in tokens {
            if let match = keywordMap[token] {
                return match
            }
        }

        // Try substring match for compound words like "pushup" or "deadlift"
        let joined = tokens.joined()
        for (keyword, suggestion) in keywordMap {
            if joined.contains(keyword) || keyword.contains(joined) {
                return suggestion
            }
        }

        // Fallback by type / metric kind
        return fallback(type: type, metricKind: metricKind)
    }

    /// Keyword-only suggestion for goals (no ActivityType needed)
    static func suggestForGoal(name: String) -> Suggestion? {
        let tokens = name.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for token in tokens {
            if let match = keywordMap[token] { return match }
        }

        let joined = tokens.joined()
        for (keyword, suggestion) in keywordMap {
            if joined.contains(keyword) || keyword.contains(joined) {
                return suggestion
            }
        }
        return nil
    }

    // MARK: - Fallbacks

    private static func fallback(type: ActivityType, metricKind: MetricKind?) -> Suggestion {
        switch type {
        case .checkbox:
            return Suggestion(icon: "checkmark.circle", color: "#4ECDC4")
        case .value:
            return Suggestion(icon: "number", color: "#45B7D1")
        case .cumulative:
            return Suggestion(icon: "chart.bar.fill", color: "#FF6B35")
        case .container:
            return Suggestion(icon: "folder.fill", color: "#A29BFE")
        case .metric:
            switch metricKind {
            case .photo:   return Suggestion(icon: "camera.fill", color: "#C44DFF")
            case .value:   return Suggestion(icon: "gauge.medium", color: "#45B7D1")
            case .checkbox: return Suggestion(icon: "flag.fill", color: "#00B894")
            case .notes:   return Suggestion(icon: "note.text", color: "#FFEAA7")
            case nil:      return Suggestion(icon: "chart.dots.scatter", color: "#74B9FF")
            }
        }
    }

    // MARK: - Keyword Dictionary

    private static let keywordMap: [String: Suggestion] = {
        var map = [String: Suggestion]()

        func add(_ keywords: [String], icon: String, color: String) {
            let s = Suggestion(icon: icon, color: color)
            for k in keywords { map[k] = s }
        }

        // ═══════════════════════════════════════
        // ── HYDRATION ──
        // ═══════════════════════════════════════
        add(["water", "hydrate", "hydration", "drink", "drinking", "fluid", "fluids",
             "liquids", "electrolyte", "electrolytes", "h2o", "sip", "sips",
             "sparkling", "seltzer", "lemon"],
            icon: "drop.fill", color: "#45B7D1")
        add(["juice", "smoothie", "smoothies", "shake", "milkshake"],
            icon: "cup.and.saucer.fill", color: "#FF6B35")

        // ═══════════════════════════════════════
        // ── EXERCISE & FITNESS ──
        // ═══════════════════════════════════════

        // General
        add(["exercise", "workout", "training", "gym", "fitness", "sweat",
             "warmup", "cooldown", "drills", "conditioning", "bootcamp",
             "crossfit", "bodyweight", "calisthenics", "functional", "circuit"],
            icon: "figure.run", color: "#FF6B35")

        // Running / Sprinting
        add(["run", "running", "jog", "jogging", "sprint", "sprinting",
             "marathon", "halfmarathon", "5k", "10k", "couch", "c25k",
             "intervals", "tempo", "fartlek", "trail"],
            icon: "figure.run", color: "#FF6B6B")

        // Walking / Hiking
        add(["walk", "walking", "steps", "hike", "hiking", "trek", "trekking",
             "stroll", "rucking", "ruck", "backpacking", "ramble"],
            icon: "figure.walk", color: "#00B894")

        // Cycling
        add(["cycle", "cycling", "bike", "biking", "bicycle", "spin",
             "spinning", "peloton", "mtb", "bmx", "velodrome"],
            icon: "bicycle", color: "#4ECDC4")

        // Swimming
        add(["swim", "swimming", "pool", "laps", "freestyle", "backstroke",
             "breaststroke", "butterfly", "diving", "snorkel", "aqua"],
            icon: "figure.pool.swim", color: "#74B9FF")

        // Yoga / Flexibility
        add(["yoga", "stretch", "stretching", "flexibility", "pilates",
             "barre", "mobility", "foam", "roller", "splits", "contortion",
             "asana", "vinyasa", "hatha", "ashtanga", "yin", "bikram"],
            icon: "figure.yoga", color: "#A29BFE")

        // Strength / Weight Training
        add(["lift", "lifting", "weights", "strength", "deadlift", "squat",
             "bench", "barbell", "dumbbell", "kettlebell", "powerlifting",
             "olympiclifting", "snatch", "cleanandjerk", "rack", "press",
             "overhead", "curl", "row", "shrug", "trap", "lat", "flywheel"],
            icon: "dumbbell.fill", color: "#E17055")

        // Bodyweight / Calisthenics
        add(["pushup", "pullup", "chinup", "burpee", "plank", "crunches",
             "situp", "abs", "dips", "lunge", "lunges", "pistol",
             "muscleup", "handstand", "lsit", "tuck", "lever", "bridges",
             "glute", "hipthrust", "legpress", "calfraise", "wallsit",
             "jumpingjack", "mountainclimber"],
            icon: "figure.strengthtraining.traditional", color: "#FF6B35")

        // Cardio / HIIT
        add(["cardio", "hiit", "aerobic", "jumping", "jump", "skipping",
             "jumprope", "stairmaster", "stepper", "elliptical", "treadmill",
             "rower", "tabata", "amrap", "emom", "metcon", "wod"],
            icon: "heart.circle.fill", color: "#FD79A8")

        // Climbing
        add(["climb", "climbing", "boulder", "bouldering", "rappel",
             "abseil", "crag", "toprope", "lead"],
            icon: "figure.climbing", color: "#E17055")

        // Martial Arts / Combat
        add(["martial", "boxing", "kickboxing", "karate", "taekwondo",
             "judo", "mma", "muaythai", "bjj", "jiujitsu", "wrestling",
             "kendo", "fencing", "kungfu", "wushu", "capoeira",
             "aikido", "hapkido", "savate", "sambo", "sparring", "selfdefense"],
            icon: "figure.martial.arts", color: "#FF6B6B")

        // Dance
        add(["dance", "dancing", "ballet", "salsa", "bachata", "tango",
             "waltz", "hiphop", "breakdance", "contemporary", "jazz",
             "tap", "swing", "zumba", "choreography", "ballroom", "samba",
             "flamenco", "kpop", "bhangra"],
            icon: "figure.dance", color: "#FD79A8")

        // Racquet Sports
        add(["tennis", "badminton", "squash", "racquet", "paddle",
             "pickleball", "pingpong", "tabletennis"],
            icon: "tennisball.fill", color: "#96CEB4")

        // Ball / Team Sports
        add(["basketball", "football", "soccer", "volleyball", "sports",
             "baseball", "softball", "cricket", "rugby", "lacrosse",
             "handball", "hockey", "fieldhockey", "waterpolo",
             "frisbee", "ultimate", "dodgeball"],
            icon: "sportscourt.fill", color: "#FF6B35")

        // Golf
        add(["golf", "putting", "driving", "teeoff", "range"],
            icon: "figure.golf", color: "#96CEB4")

        // Winter Sports
        add(["ski", "skiing", "snowboard", "snowboarding", "iceskate",
             "iceskating", "curling", "bobsled", "luge", "crosscountry",
             "nordic", "snowshoe"],
            icon: "figure.skiing.downhill", color: "#74B9FF")

        // Water Sports
        add(["rowing", "kayak", "canoe", "paddle", "surf", "surfing",
             "wakeboard", "waterski", "sail", "sailing", "windsurf",
             "kitesurf", "standup", "sup", "paddleboard", "rafting",
             "jetski", "scuba"],
            icon: "figure.rowing", color: "#45B7D1")

        // Grip / Hanging
        add(["deadhang", "hang", "grip", "gripstrength", "forearm",
             "wrist", "fingerboard", "hangboard"],
            icon: "hand.raised.fill", color: "#E17055")

        // Equestrian
        add(["horse", "riding", "equestrian", "polo", "dressage", "showjumping"],
            icon: "figure.equestrian.sports", color: "#A2845E")

        // Archery / Shooting
        add(["archery", "bow", "arrow", "shoot", "shooting", "target",
             "rifle", "pistol", "marksmanship"],
            icon: "scope", color: "#8E8E93")

        // Track & Field
        add(["hurdle", "hurdles", "javelin", "shotput", "discus",
             "highjump", "longjump", "polevault", "decathlon", "relay",
             "track", "field", "100m", "200m", "400m", "800m"],
            icon: "figure.track.and.field", color: "#FF6B35")

        // Gymnastics
        add(["gymnastics", "tumbling", "trampoline", "pommel",
             "vault", "rings", "parallel", "unevenbars"],
            icon: "figure.gymnastics", color: "#FD79A8")

        // ═══════════════════════════════════════
        // ── NUTRITION & FOOD ──
        // ═══════════════════════════════════════
        add(["eat", "eating", "food", "meal", "meals", "calories", "calorie",
             "diet", "nutrition", "macros", "macro", "iifym", "portion",
             "mealprep", "prep", "keto", "paleo", "vegan", "vegetarian",
             "whole30", "lowcarb", "glutenfree", "dairyfree"],
            icon: "fork.knife", color: "#FF6B6B")
        add(["cook", "cooking", "recipe", "recipes", "kitchen", "bake",
             "baking", "grill", "grilling", "roast", "saute", "stew",
             "simmer", "chop", "prep", "marinate"],
            icon: "frying.pan.fill", color: "#E17055")
        add(["fruit", "fruits", "vegetable", "vegetables", "veggies",
             "salad", "greens", "fiber", "micronutrient", "antioxidant",
             "organic", "wholefood", "superfood"],
            icon: "leaf.fill", color: "#00B894")
        add(["protein", "supplement", "supplements", "vitamins", "vitamin",
             "creatine", "probiotic", "prebiotic", "omega", "collagen",
             "magnesium", "zinc", "iron", "calcium", "b12", "d3",
             "ashwagandha", "turmeric", "fishoil", "bcaa", "glutamine",
             "multivitamin", "capsule", "tablet", "powder"],
            icon: "pills.fill", color: "#A29BFE")
        add(["coffee", "tea", "caffeine", "espresso", "latte",
             "matcha", "chai", "decaf", "americano", "cappuccino",
             "herbal", "greentea", "kombucha"],
            icon: "cup.and.saucer.fill", color: "#E17055")
        add(["breakfast", "lunch", "dinner", "snack", "supper",
             "brunch", "appetizer", "dessert", "mealtime"],
            icon: "takeoutbag.and.cup.and.straw.fill", color: "#FF6B35")
        add(["fast", "fasting", "intermittent", "omad", "16:8", "18:6",
             "24h", "autophagy", "ramadan"],
            icon: "clock.badge.xmark", color: "#FFEAA7")
        add(["alcohol", "beer", "wine", "sober", "sobriety", "dryjanuary",
             "bourbon", "whiskey", "cocktail", "spirits", "nodrink",
             "mocktail", "abstain"],
            icon: "wineglass.fill", color: "#C44DFF")

        // ═══════════════════════════════════════
        // ── SLEEP & REST ──
        // ═══════════════════════════════════════
        add(["sleep", "sleeping", "bedtime", "bed", "nap", "rest",
             "insomnia", "snore", "rem", "deepsleep", "lightsleep",
             "sleephygiene", "circadian", "melatonin", "nighttime",
             "shuteye", "siesta", "powernap", "slumber"],
            icon: "moon.fill", color: "#A29BFE")
        add(["wake", "wakeup", "alarm", "morning", "riseandshine",
             "earlybird", "sunrise", "dawn", "getup"],
            icon: "sunrise.fill", color: "#FFEAA7")

        // ═══════════════════════════════════════
        // ── MINDFULNESS & MENTAL HEALTH ──
        // ═══════════════════════════════════════
        add(["meditate", "meditation", "mindfulness", "mindful", "zen",
             "vipassana", "transcendental", "bodyscan", "lovingkindness",
             "metta", "centering", "grounding", "headspace", "calm",
             "insight"],
            icon: "brain.head.profile.fill", color: "#A29BFE")
        add(["breathe", "breathing", "breathwork", "pranayama",
             "wim", "wimhof", "boxbreathing", "478",
             "deepbreath", "diaphragmatic", "nostril"],
            icon: "wind", color: "#74B9FF")
        add(["journal", "journaling", "diary", "reflect", "reflection",
             "morningpages", "bulletjournal", "bujo", "freewrite",
             "thoughtdump", "braindump", "memoir", "logbook"],
            icon: "book.fill", color: "#FFEAA7")
        add(["gratitude", "grateful", "thankful", "affirmation",
             "affirmations", "mantra", "mantras", "positive",
             "selfaffirmation", "blessing", "blessings", "appreciate"],
            icon: "heart.fill", color: "#FD79A8")
        add(["therapy", "therapist", "counseling", "mental", "cbt",
             "dbt", "emdr", "psychotherapy", "psychiatric", "psych",
             "counselor", "mentalhealth", "selfcare", "selflove",
             "selfworth", "selfesteem", "innochild", "shadow"],
            icon: "brain.fill", color: "#C44DFF")
        add(["mood", "emotion", "emotions", "feeling", "feelings",
             "checkin", "moodlog", "moodtracker", "wellbeing",
             "happiness", "happy", "sad", "anger", "fear", "joy"],
            icon: "face.smiling.fill", color: "#FFEAA7")
        add(["stress", "relax", "relaxation", "calm", "anxiety",
             "decompress", "unwind", "destress", "peace", "tranquil",
             "chill", "serene", "soothe", "recovery"],
            icon: "leaf.fill", color: "#96CEB4")

        // ═══════════════════════════════════════
        // ── READING & LEARNING ──
        // ═══════════════════════════════════════
        add(["read", "reading", "book", "books", "pages", "literature",
             "fiction", "nonfiction", "novel", "chapter", "kindle",
             "ebook", "hardcover", "paperback", "library", "bookclub",
             "goodreads", "bibliography"],
            icon: "book.fill", color: "#74B9FF")
        add(["study", "studying", "learn", "learning", "course", "class",
             "lecture", "tutorial", "curriculum", "syllabus", "homework",
             "assignment", "exam", "test", "quiz", "revision",
             "certification", "certificate", "mooc", "coursera",
             "udemy", "edx", "khan", "masterclass"],
            icon: "graduationcap.fill", color: "#45B7D1")
        add(["language", "vocab", "vocabulary", "duolingo", "flashcard",
             "flashcards", "anki", "spanish", "french", "german",
             "mandarin", "japanese", "korean", "arabic", "hindi",
             "portuguese", "italian", "russian", "chinese", "polyglot",
             "immersion", "grammar", "conjugation", "translation"],
            icon: "character.book.closed.fill", color: "#4ECDC4")
        add(["podcast", "podcasts", "audiobook", "audiobooks", "listen",
             "audible", "spotify", "overcast", "episode"],
            icon: "headphones", color: "#C44DFF")
        add(["news", "newspaper", "article", "articles", "current",
             "events", "newsletter", "rss", "feed", "substack"],
            icon: "newspaper.fill", color: "#74B9FF")
        add(["research", "paper", "papers", "thesis", "dissertation",
             "academic", "journal", "peer", "citation", "scholar"],
            icon: "doc.text.magnifyingglass", color: "#45B7D1")
        add(["math", "maths", "algebra", "calculus", "geometry",
             "statistics", "probability", "leetcode", "algorithm",
             "algorithms", "datastructure", "puzzle", "logic"],
            icon: "function", color: "#4ECDC4")
        add(["science", "physics", "chemistry", "biology",
             "astronomy", "geology", "lab", "experiment"],
            icon: "atom", color: "#74B9FF")
        add(["history", "philosophy", "sociology", "psychology",
             "economics", "politics", "anthropology"],
            icon: "building.columns.fill", color: "#A29BFE")

        // ═══════════════════════════════════════
        // ── WORK & PRODUCTIVITY ──
        // ═══════════════════════════════════════
        add(["work", "working", "office", "task", "tasks", "todo",
             "todolist", "productivity", "efficient", "hustle",
             "grind", "deliverable", "deadline", "sprint",
             "agile", "scrum", "kanban", "backlog", "jira"],
            icon: "briefcase.fill", color: "#45B7D1")
        add(["code", "coding", "program", "programming", "develop",
             "development", "dev", "debug", "deploy", "commit",
             "github", "gitlab", "repo", "refactor", "review",
             "pullrequest", "pr", "merge", "branch", "terminal",
             "api", "backend", "frontend", "fullstack", "devops",
             "software", "engineer", "engineering", "hackathon",
             "swift", "python", "javascript", "typescript", "rust",
             "java", "kotlin", "react", "flutter", "ios", "android"],
            icon: "chevron.left.forwardslash.chevron.right", color: "#4ECDC4")
        add(["email", "emails", "inbox", "mail", "newsletter",
             "unsubscribe", "inboxzero", "correspondence"],
            icon: "envelope.fill", color: "#74B9FF")
        add(["meeting", "meetings", "call", "standup", "1on1",
             "oneonone", "sync", "huddle", "standup", "retro",
             "retrospective", "demo", "presentation", "pitch",
             "interview", "zoom", "teams", "slack", "conference"],
            icon: "person.2.fill", color: "#A29BFE")
        add(["write", "writing", "blog", "essay", "content",
             "copywriting", "screenplay", "script", "draft",
             "proofread", "edit", "publish", "author", "wordcount",
             "medium", "substack", "wordpress"],
            icon: "pencil.line", color: "#FFEAA7")
        add(["plan", "planning", "organize", "review", "agenda",
             "schedule", "calendar", "prioritize", "timeblock",
             "batch", "weekly", "quarterly", "retrospective"],
            icon: "list.clipboard.fill", color: "#96CEB4")
        add(["focus", "deep", "pomodoro", "timer", "flowstate",
             "concentration", "distraction", "dnd", "donotdisturb",
             "deepwork", "focused", "intention", "intentional"],
            icon: "timer", color: "#FF6B35")
        add(["project", "projects", "milestone", "roadmap",
             "initiative", "objective", "okr", "kpi", "strategy"],
            icon: "folder.fill", color: "#45B7D1")
        add(["network", "networking", "linkedin", "connection",
             "connections", "mentor", "mentorship", "coaching",
             "coach", "career", "resume", "portfolio", "cv"],
            icon: "person.crop.rectangle.stack.fill", color: "#A29BFE")

        // ═══════════════════════════════════════
        // ── SELF-CARE & HYGIENE ──
        // ═══════════════════════════════════════
        add(["skincare", "skin", "moisturize", "sunscreen", "spf",
             "retinol", "serum", "toner", "cleanser", "exfoliate",
             "mask", "facemask", "acne", "pimple", "derma",
             "niacinamide", "hyaluronic", "peptide", "collagen",
             "antiaging", "wrinkle", "glow", "complexion"],
            icon: "drop.circle.fill", color: "#FD79A8")
        add(["shower", "bath", "hygiene", "groom", "grooming",
             "bodywash", "soap", "loofah", "exfoliate", "soak",
             "selfgroom", "manscape", "wax", "shave", "shaving"],
            icon: "shower.fill", color: "#74B9FF")
        add(["teeth", "brush", "floss", "dental", "mouthwash",
             "toothbrush", "toothpaste", "whitening", "retainer",
             "braces", "dentist", "oral", "gum", "cavity", "tongue"],
            icon: "mouth.fill", color: "#4ECDC4")
        add(["hair", "haircare", "shampoo", "conditioner", "blowdry",
             "hairstyle", "trim", "haircut", "barber", "salon",
             "keratin", "oiling", "scalp", "dandruff"],
            icon: "comb.fill", color: "#FD79A8")
        add(["nails", "manicure", "pedicure", "nail", "cuticle",
             "polish", "gelpolish", "hands", "feet"],
            icon: "hand.raised.fingers.spread.fill", color: "#FD79A8")
        add(["spa", "massage", "bodywork", "sauna", "steam",
             "hotspring", "jacuzzi", "facial", "aromatherapy",
             "essential", "oils", "pamper", "treat"],
            icon: "sparkles", color: "#C44DFF")

        // ═══════════════════════════════════════
        // ── HEALTH & MEDICAL ──
        // ═══════════════════════════════════════
        add(["medicine", "medication", "pills", "prescription", "meds",
             "drug", "dose", "dosage", "refill", "pharmacy",
             "otc", "aspirin", "ibuprofen", "antibiotic", "inhaler",
             "epipen", "injection", "shot", "vaccine"],
            icon: "pills.fill", color: "#FF6B6B")
        add(["doctor", "appointment", "checkup", "hospital", "clinic",
             "physical", "annual", "screening", "bloodwork", "lab",
             "xray", "mri", "ultrasound", "referral", "specialist",
             "ent", "dermatologist", "ophthalmologist", "cardiologist",
             "orthopedic", "urologist", "gyno", "ob", "obgyn",
             "pediatrician", "surgeon", "followup", "dentist"],
            icon: "cross.case.fill", color: "#FF6B6B")
        add(["weight", "weigh", "scale", "bmi", "bodyfat",
             "bodycomp", "composition", "lean", "mass",
             "dexa", "calipers", "waist", "hip", "circumference",
             "measurements", "bulking", "cutting", "recomp"],
            icon: "scalemass.fill", color: "#E17055")
        add(["blood", "pressure", "glucose", "sugar", "insulin",
             "cholesterol", "triglyceride", "a1c", "hemoglobin",
             "iron", "ferritin", "thyroid", "tsh", "cortisol",
             "testosterone", "estrogen", "vitamin", "cbc", "crp",
             "liver", "kidney", "metabolic", "panel"],
            icon: "heart.text.square.fill", color: "#FF6B6B")
        add(["posture", "ergonomic", "back", "spine", "neck",
             "shoulder", "alignment", "chiropractor", "chiro",
             "physio", "physiotherapy", "pt", "rehab",
             "rehabilitation", "recovery", "icing", "tens"],
            icon: "figure.stand", color: "#96CEB4")
        add(["eye", "eyes", "vision", "eyedrops", "contacts",
             "glasses", "optometrist", "eyecare", "blulight",
             "bluelight", "screenbreak", "2020", "eyetest"],
            icon: "eye.fill", color: "#45B7D1")
        add(["heartrate", "heart", "pulse", "bpm", "resting",
             "hrv", "variability", "ecg", "ekg", "cardio",
             "vo2", "vo2max", "lactate", "zones"],
            icon: "heart.fill", color: "#FF6B6B")
        add(["temperature", "temp", "fever", "thermometer",
             "basal", "bbt"],
            icon: "thermometer.medium", color: "#FF6B35")
        add(["oxygen", "spo2", "saturation", "oximeter", "breathing"],
            icon: "lungs.fill", color: "#74B9FF")
        add(["period", "menstrual", "cycle", "ovulation", "fertility",
             "pms", "cramp", "flow", "luteal", "follicular"],
            icon: "calendar.circle.fill", color: "#FD79A8")

        // ═══════════════════════════════════════
        // ── FINANCE ──
        // ═══════════════════════════════════════
        add(["money", "finance", "budget", "saving", "savings",
             "invest", "investing", "investment", "portfolio",
             "stock", "stocks", "etf", "bond", "bonds", "mutual",
             "crypto", "bitcoin", "ethereum", "401k", "ira",
             "roth", "compound", "dividend", "networth",
             "financialfreedom", "fire", "retire", "retirement"],
            icon: "dollarsign.circle.fill", color: "#00B894")
        add(["spend", "spending", "expense", "expenses", "track",
             "bill", "bills", "rent", "mortgage", "insurance",
             "tax", "taxes", "debt", "loan", "creditcard",
             "payment", "subscription", "subscriptions", "receipt"],
            icon: "creditcard.fill", color: "#FF6B35")
        add(["income", "salary", "wage", "earnings", "revenue",
             "sidehustle", "freelance", "gig", "bonus", "raise",
             "paycheck", "commission"],
            icon: "banknote.fill", color: "#00B894")

        // ═══════════════════════════════════════
        // ── SOCIAL & RELATIONSHIPS ──
        // ═══════════════════════════════════════
        add(["family", "kids", "children", "parenting", "parent",
             "mom", "dad", "mother", "father", "son", "daughter",
             "sibling", "sister", "brother", "grandparent",
             "grandma", "grandpa", "baby", "toddler", "infant",
             "diaper", "feeding", "bedtimestory", "playtime",
             "qualitytime"],
            icon: "figure.2.and.child.holdinghands", color: "#FD79A8")
        add(["friends", "social", "hangout", "socialize",
             "gathering", "party", "gettogether", "reunion",
             "catchup", "bond", "bonding", "community",
             "meetup", "group", "club"],
            icon: "person.3.fill", color: "#A29BFE")
        add(["date", "dating", "partner", "relationship",
             "spouse", "husband", "wife", "boyfriend", "girlfriend",
             "romance", "romantic", "anniversary", "datenight",
             "love", "intimacy", "couple", "together"],
            icon: "heart.circle.fill", color: "#FD79A8")
        add(["phone", "contact", "chat", "text", "message",
             "callhome", "facetime", "videocall", "whatsapp",
             "imessage", "telegram", "signal", "discord"],
            icon: "phone.fill", color: "#4ECDC4")
        add(["volunteer", "volunteering", "charity", "donate",
             "donation", "giveback", "nonprofit", "service",
             "community", "help", "helping", "kindness",
             "randomact", "gooddeed"],
            icon: "hand.raised.fill", color: "#00B894")

        // ═══════════════════════════════════════
        // ── CREATIVE & HOBBIES ──
        // ═══════════════════════════════════════
        add(["draw", "drawing", "sketch", "sketching", "art",
             "paint", "painting", "illustration", "illustrate",
             "watercolor", "oil", "acrylic", "pastel", "charcoal",
             "pencil", "ink", "calligraphy", "lettering",
             "doodle", "comic", "manga", "anime", "digital",
             "procreate", "ipad", "canvas", "easel", "portrait",
             "landscape", "abstract"],
            icon: "paintbrush.fill", color: "#C44DFF")
        add(["music", "instrument", "piano", "guitar", "sing",
             "singing", "practice", "ukulele", "bass", "drums",
             "violin", "viola", "cello", "flute", "clarinet",
             "saxophone", "trumpet", "trombone", "harmonica",
             "banjo", "mandolin", "harp", "accordion", "keyboard",
             "synthesizer", "dj", "beat", "beatmaking", "produce",
             "producing", "composition", "songwriter", "vocal",
             "vocals", "choir", "acapella", "karaoke",
             "scales", "chords", "tabs", "sheetmusic"],
            icon: "music.note", color: "#FD79A8")
        add(["photo", "photography", "camera", "pictures", "pic",
             "portrait", "landscape", "macro", "street",
             "lightroom", "photoshop", "edit", "editing",
             "darkroom", "exposure", "composition", "aperture",
             "shutter", "lens", "film", "analog", "drone"],
            icon: "camera.fill", color: "#C44DFF")
        add(["craft", "crafts", "knit", "knitting", "sew", "sewing",
             "crochet", "embroider", "embroidery", "quilt",
             "quilting", "weave", "weaving", "macrame",
             "pottery", "ceramic", "ceramics", "clay",
             "woodwork", "woodworking", "carve", "carving",
             "sculpture", "origami", "papercraft", "scrapbook",
             "scrapbooking", "beading", "jewelry", "leatherwork"],
            icon: "scissors", color: "#E17055")
        add(["garden", "gardening", "plants", "plant", "planting",
             "flower", "flowers", "herb", "herbs", "compost",
             "soil", "seed", "seeds", "prune", "pruning",
             "harvest", "greenhouse", "terrarium", "succulent",
             "bonsai", "orchid", "lawn", "mow", "mowing",
             "landscape", "landscaping", "weed", "weeding",
             "mulch", "fertilize", "houseplant", "repot"],
            icon: "leaf.fill", color: "#00B894")
        add(["game", "gaming", "videogame", "play", "xbox",
             "playstation", "nintendo", "switch", "pc",
             "steam", "esports", "boardgame", "tabletop",
             "chess", "checkers", "puzzle", "puzzles",
             "crossword", "sudoku", "wordle", "trivia",
             "cardgame", "poker", "dnd", "roleplay", "rpg",
             "strategy", "simulation"],
            icon: "gamecontroller.fill", color: "#A29BFE")
        add(["movie", "movies", "film", "films", "cinema",
             "watch", "watching", "tv", "show", "shows",
             "series", "binge", "netflix", "hulu", "hbo",
             "disney", "streaming", "documentary"],
            icon: "film.fill", color: "#C44DFF")

        // ═══════════════════════════════════════
        // ── HOME & CHORES ──
        // ═══════════════════════════════════════
        add(["clean", "cleaning", "chores", "chore", "tidy",
             "declutter", "minimalism", "konmari", "scrub",
             "mop", "mopping", "sweep", "sweeping", "dust",
             "dusting", "wipe", "sanitize", "disinfect",
             "deepclean", "springclean"],
            icon: "bubbles.and.sparkles.fill", color: "#4ECDC4")
        add(["laundry", "wash", "dishes", "vacuum", "vacuuming",
             "iron", "ironing", "fold", "folding", "dryer",
             "hangdry", "bleach", "stain", "detergent"],
            icon: "washer.fill", color: "#74B9FF")
        add(["organize", "sort", "arrange", "storage", "closet",
             "pantry", "garage", "attic", "basement", "shelf",
             "drawer", "container", "label", "filing"],
            icon: "tray.2.fill", color: "#96CEB4")
        add(["repair", "fix", "maintenance", "maintain", "diy",
             "handyman", "plumbing", "electrical", "paint",
             "renovation", "remodel", "install", "assemble",
             "build", "construction", "tool", "tools"],
            icon: "wrench.and.screwdriver.fill", color: "#E17055")
        add(["grocery", "groceries", "shopping", "shop",
             "errand", "errands", "pickup", "delivery",
             "instacart", "amazon", "costco", "walmart",
             "target", "order", "restock", "pantry"],
            icon: "cart.fill", color: "#FF6B35")
        add(["pet", "dog", "cat", "puppy", "kitten", "fish",
             "bird", "hamster", "rabbit", "guinea", "turtle",
             "reptile", "aquarium", "terrarium", "vet",
             "veterinary", "groom", "feeding", "litter",
             "walkdog", "petsitting", "dogsitting"],
            icon: "pawprint.fill", color: "#E17055")
        add(["car", "vehicle", "auto", "oil", "tire", "tires",
             "gas", "fuel", "carwash", "inspection", "mechanic",
             "registration", "smog", "detailing"],
            icon: "car.fill", color: "#8E8E93")

        // ═══════════════════════════════════════
        // ── SPIRITUAL & RELIGIOUS ──
        // ═══════════════════════════════════════
        add(["pray", "prayer", "prayers", "church", "mosque",
             "temple", "worship", "devotion", "devotional",
             "mass", "sermon", "liturgy", "hymn", "hymns",
             "vespers", "matins", "lauds", "compline",
             "rosary", "novena", "adoration", "communion",
             "confession", "sacrament", "fellowship",
             "sabbath", "shabbat", "synagogue", "minyan",
             "namaz", "salah", "salat", "dua", "dhikr",
             "tasbih", "istighfar", "tahajjud", "sunnah",
             "jumma", "eid", "iftar", "suhoor",
             "puja", "aarti", "mandir", "kirtan", "bhajan",
             "satsang", "seva"],
            icon: "hands.and.sparkles.fill", color: "#FFEAA7")
        add(["quran", "bible", "scripture", "dharma", "spiritual",
             "torah", "talmud", "hadith", "sunnah", "vedas",
             "gita", "bhagavad", "sutra", "tripitaka",
             "guru", "granth", "sahib", "psalm", "proverbs",
             "gospel", "testament", "verse", "ayah", "surah",
             "shloka", "chapter"],
            icon: "book.closed.fill", color: "#A29BFE")

        // ═══════════════════════════════════════
        // ── TRAVEL & OUTDOORS ──
        // ═══════════════════════════════════════
        add(["travel", "trip", "vacation", "explore",
             "adventure", "journey", "roadtrip", "sightseeing",
             "tourist", "tourism", "passport", "visa",
             "flight", "airport", "hotel", "hostel",
             "airbnb", "booking", "itinerary", "packing",
             "luggage", "souvenir", "wanderlust", "nomad"],
            icon: "airplane", color: "#45B7D1")
        add(["outdoor", "outdoors", "nature", "park", "forest",
             "mountain", "mountains", "beach", "ocean", "sea",
             "lake", "river", "waterfall", "canyon", "desert",
             "jungle", "rainforest", "savanna", "prairie",
             "meadow", "valley", "island", "coast", "cliff",
             "cave", "camping", "campfire", "tent", "bonfire",
             "stargazing", "birdwatching", "fishing", "hunt",
             "hunting", "wildlife", "safari"],
            icon: "tree.fill", color: "#00B894")
        add(["sun", "sunshine", "sunlight", "daylight", "outside",
             "fresh", "freshair", "uv", "tan", "tanning",
             "vitamin", "solar", "bright"],
            icon: "sun.max.fill", color: "#FFEAA7")

        // ═══════════════════════════════════════
        // ── SCREEN TIME & DIGITAL WELLNESS ──
        // ═══════════════════════════════════════
        add(["screen", "screentime", "digital", "detox", "unplug",
             "disconnect", "offline", "noscreen", "phonefree",
             "techfree", "dopamine", "dopaminefast", "scroll",
             "scrolling", "doom", "doomscroll", "notification",
             "notifications", "appusage", "limit"],
            icon: "iphone.slash", color: "#C44DFF")
        add(["socialmedia", "instagram", "twitter", "tiktok",
             "youtube", "reddit", "facebook", "snapchat",
             "linkedin", "pinterest", "twitch", "tumblr",
             "threads", "bluesky", "mastodon", "x"],
            icon: "bubble.left.and.bubble.right.fill", color: "#FD79A8")

        // ═══════════════════════════════════════
        // ── ENVIRONMENT & SUSTAINABILITY ──
        // ═══════════════════════════════════════
        add(["recycle", "recycling", "compost", "composting",
             "zerowaste", "sustainable", "sustainability",
             "ecofriendly", "green", "reuse", "reduce",
             "carbonfootprint", "emissions", "solar",
             "electric", "ev", "transit", "publictransit",
             "bike", "carpool", "conserve", "conservation"],
            icon: "arrow.3.trianglepath", color: "#00B894")

        // ═══════════════════════════════════════
        // ── MISCELLANEOUS ──
        // ═══════════════════════════════════════
        add(["habit", "habits", "routine", "daily", "streak",
             "consistency", "discipline", "ritual", "rituals",
             "practice", "deliberate", "compounding", "chain",
             "dontbreakthechain", "atomic", "micro"],
            icon: "flame.fill", color: "#FF6B35")
        add(["goal", "goals", "target", "milestone", "achieve",
             "achievement", "progress", "growth", "improve",
             "improvement", "level", "levelup", "upgrade",
             "transform", "transformation", "journey",
             "resolution", "bucket", "bucketlist", "dream",
             "vision", "visionboard", "manifest"],
            icon: "target", color: "#FF6B6B")
        add(["challenge", "dare", "competition", "compete",
             "contest", "bet", "wager", "30day", "75hard",
             "100day", "streak", "undertaking"],
            icon: "bolt.fill", color: "#FFEAA7")
        add(["log", "logging", "record", "tracking", "measure",
             "data", "analytics", "metric", "metrics",
             "quantified", "quantify", "selftracking",
             "biohack", "biohacking", "optimize", "optimization"],
            icon: "list.bullet.clipboard.fill", color: "#4ECDC4")
        add(["morning", "morningroutine", "eveningroutine",
             "nightroutine", "bedtimeroutine", "wakeup",
             "routine", "winday", "shutdown", "winddown",
             "power", "miracle", "5am", "4am"],
            icon: "sunrise.fill", color: "#FFEAA7")
        add(["cold", "coldshower", "coldplunge", "icebath",
             "cryotherapy", "contrast", "contrastshower",
             "wimhof", "coldexposure", "polar", "dip"],
            icon: "snowflake", color: "#74B9FF")
        add(["gratitudejournal", "thankfulness", "grateful",
             "appreciation", "counting", "blessings"],
            icon: "heart.fill", color: "#FD79A8")

        return map
    }()

    // MARK: - Category Suggestion

    /// Maps activity name keywords → default category name for smart autofill.
    /// Returns a category name string; caller matches against actual Category objects.
    static func suggestCategory(for name: String) -> String? {
        let words = name.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for word in words {
            if let category = categoryKeywordMap[word] {
                return category
            }
        }
        return nil
    }

    private static let categoryKeywordMap: [String: String] = {
        var map = [String: String]()

        func add(_ keywords: [String], category: String) {
            for kw in keywords { map[kw] = category }
        }

        // Workout
        add(["run", "running", "walk", "walking", "jog", "jogging",
             "swim", "swimming", "cycle", "cycling", "bike", "biking",
             "yoga", "stretch", "stretching", "pilates", "barre", "mobility",
             "lift", "lifting", "weights", "strength", "deadlift", "squat", "bench",
             "pushup", "pullup", "chinup", "burpee", "plank", "crunches", "situp",
             "dips", "lunge", "lunges", "muscleup", "handstand", "calfraise",
             "cardio", "hiit", "aerobic", "jumping", "skipping", "jumprope",
             "exercise", "workout", "gym", "fitness", "training", "sweat",
             "warmup", "cooldown", "conditioning", "bootcamp", "crossfit",
             "calisthenics", "bodyweight", "circuit", "functional",
             "row", "rowing", "deadhang", "hang", "grip", "kettlebell",
             "steps", "basketball", "football", "soccer", "tennis", "golf",
             "climb", "climbing", "hike", "hiking", "sprint", "marathon",
             "dance", "dancing", "ballet", "salsa", "zumba",
             "boxing", "kickboxing", "karate", "taekwondo", "judo", "mma",
             "bjj", "jiujitsu", "wrestling", "fencing", "martial",
             "ski", "skiing", "snowboard", "snowboarding",
             "surf", "surfing", "kayak", "canoe", "paddleboard",
             "volleyball", "baseball", "cricket", "rugby", "lacrosse",
             "badminton", "squash", "pickleball", "tabletennis",
             "gymnastics", "trampoline", "tumbling",
             "stairmaster", "elliptical", "treadmill",
             "tabata", "amrap", "emom", "wod",
             "equestrian", "horse", "archery",
             "track", "field", "hurdle", "javelin",
             "coldplunge", "icebath", "coldshower"],
            category: "Workout")

        // Supplement
        add(["vitamin", "vitamins", "supplement", "supplements",
             "creatine", "protein", "collagen", "probiotic", "prebiotic",
             "omega", "fishoil", "bcaa", "glutamine",
             "magnesium", "zinc", "iron", "calcium", "b12", "d3",
             "fish", "pill", "pills", "capsule", "tablet", "powder",
             "ashwagandha", "turmeric", "melatonin", "multivitamin"],
            category: "Supplement")

        // Hygiene
        add(["shower", "bath", "brush", "floss", "teeth", "dental",
             "skincare", "skin", "moisturize", "sunscreen", "spf", "retinol",
             "serum", "toner", "cleanser", "exfoliate", "facemask",
             "niacinamide", "hyaluronic", "peptide",
             "hair", "haircare", "shampoo", "conditioner", "salon", "barber",
             "groom", "grooming", "shave", "shaving", "wax",
             "hygiene", "wash", "clean", "mouthwash", "deodorant",
             "toothbrush", "toothpaste", "whitening", "retainer",
             "nails", "manicure", "pedicure", "cuticle"],
            category: "Hygiene")

        // Medical
        add(["medicine", "medication", "doctor", "appointment",
             "therapy", "therapist", "checkup", "bloodwork", "lab",
             "prescription", "medical", "health", "dentist",
             "blood", "pressure", "glucose", "insulin", "inhaler",
             "vaccine", "injection", "shot", "pharmacy",
             "xray", "mri", "ultrasound", "screening",
             "cardiologist", "dermatologist", "ophthalmologist",
             "orthopedic", "surgeon", "specialist", "referral",
             "chiropractor", "physio", "physiotherapy", "rehab",
             "cbt", "dbt", "emdr", "psychotherapy", "counseling",
             "cholesterol", "thyroid", "cortisol", "testosterone",
             "a1c", "hemoglobin", "ferritin", "metabolic"],
            category: "Medical")

        // Skills
        add(["read", "reading", "study", "studying", "learn", "learning",
             "course", "class", "practice", "code", "coding", "programming",
             "write", "writing", "journal", "journaling",
             "language", "spanish", "french", "mandarin", "japanese",
             "korean", "arabic", "hindi", "german", "italian", "portuguese",
             "guitar", "piano", "music", "instrument", "violin", "drums",
             "ukulele", "bass", "flute", "saxophone", "trumpet",
             "draw", "drawing", "paint", "painting", "sketch",
             "skill", "skills", "leetcode", "algorithm",
             "book", "books", "podcast", "meditate", "meditation",
             "math", "physics", "chemistry", "biology", "science",
             "philosophy", "history", "economics", "psychology",
             "certification", "mooc", "coursera", "udemy",
             "flashcard", "flashcards", "anki", "duolingo",
             "calligraphy", "lettering", "photography"],
            category: "Skills")

        // Tracking
        add(["weight", "weigh", "measure", "track", "tracking", "log",
             "water", "hydration", "sleep", "calories", "calorie",
             "mood", "energy", "heart", "heartrate", "temperature",
             "bmi", "body", "waist", "steps", "screen", "screentime",
             "budget", "expense", "saving", "savings", "spending",
             "bodyfat", "bodycomp", "dexa", "circumference",
             "hrv", "vo2", "vo2max", "spo2", "oxygen",
             "period", "menstrual", "ovulation", "fertility",
             "biohack", "quantified", "data", "analytics"],
            category: "Tracking")

        // Chores
        add(["clean", "cleaning", "chores", "chore", "tidy", "declutter",
             "laundry", "dishes", "vacuum", "mop", "sweep", "dust",
             "organize", "sort", "arrange", "storage",
             "repair", "fix", "maintenance", "diy",
             "grocery", "groceries", "shopping", "errand", "errands",
             "car", "carwash", "oil", "tire", "gas",
             "cook", "cooking", "bake", "baking", "grill",
             "pet", "dog", "cat", "vet", "litter",
             "garden", "gardening", "plants", "mow", "lawn",
             "ironing", "fold", "folding"],
            category: "Chores")

        // Spirituality
        add(["pray", "prayer", "prayers", "church", "mosque", "temple",
             "worship", "devotion", "devotional", "sermon", "mass",
             "quran", "bible", "scripture", "dharma", "spiritual",
             "torah", "hadith", "vedas", "gita", "sutra",
             "namaz", "salah", "dua", "dhikr", "tasbih",
             "puja", "aarti", "kirtan", "bhajan", "satsang",
             "rosary", "novena", "communion", "sabbath", "shabbat",
             "gratitude", "grateful", "thankful", "affirmation", "blessing"],
            category: "Spirituality")

        // Self-Care
        add(["spa", "massage", "sauna", "steam", "jacuzzi",
             "aromatherapy", "pamper", "selfcare", "selflove",
             "relax", "relaxation", "calm", "destress", "unwind",
             "breathe", "breathing", "breathwork", "pranayama",
             "mindfulness", "mindful", "zen", "coldplunge", "icebath"],
            category: "Self-Care")

        // Social
        add(["family", "kids", "children", "parenting",
             "friends", "social", "hangout", "date", "dating",
             "party", "gathering", "reunion", "catchup",
             "volunteer", "volunteering", "charity", "donate",
             "phone", "call", "chat", "message", "facetime"],
            category: "Social")

        // Outdoor
        add(["outdoor", "outdoors", "nature", "park", "forest",
             "mountain", "beach", "ocean", "lake", "river",
             "camping", "campfire", "tent", "stargazing",
             "fishing", "birdwatching", "wildlife", "safari",
             "travel", "trip", "vacation", "explore", "adventure",
             "sun", "sunshine", "sunlight", "outside", "freshair"],
            category: "Outdoor")

        // Creative
        add(["art", "craft", "crafts", "knit", "knitting", "sew", "sewing",
             "crochet", "pottery", "ceramic", "clay", "woodwork",
             "sculpture", "origami", "scrapbook", "jewelry",
             "sing", "singing", "vocal", "choir", "karaoke",
             "photo", "camera", "film", "video",
             "game", "gaming", "chess", "puzzle", "boardgame"],
            category: "Creative")

        // Finance
        add(["money", "finance", "invest", "investing", "investment",
             "stock", "stocks", "etf", "crypto", "bitcoin",
             "401k", "ira", "roth", "dividend", "networth",
             "income", "salary", "freelance", "sidehustle",
             "bill", "bills", "rent", "mortgage", "tax", "taxes",
             "debt", "loan", "subscription", "subscriptions"],
            category: "Finance")

        // Screen Time
        add(["screentime", "digital", "detox", "unplug", "disconnect",
             "dopamine", "dopaminefast", "doomscroll", "scroll",
             "instagram", "twitter", "tiktok", "youtube", "reddit",
             "facebook", "snapchat", "socialmedia",
             "notification", "notifications", "appusage"],
            category: "Screen Time")

        return map
    }()

    // MARK: - Unit Suggestion

    /// Suggests a default unit abbreviation based on activity name keywords.
    static func suggestUnit(for name: String) -> String? {
        let words = name.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for word in words {
            if let unit = unitKeywordMap[word] {
                return unit
            }
        }
        return nil
    }

    private static let unitKeywordMap: [String: String] = {
        var map = [String: String]()

        func add(_ keywords: [String], unit: String) {
            for kw in keywords { map[kw] = unit }
        }

        // Distance (US: miles)
        add(["run", "running", "jog", "jogging", "walk", "walking",
             "hike", "hiking", "sprint", "distance", "marathon", "halfmarathon",
             "5k", "10k", "trail", "rucking", "ruck", "backpacking",
             "cycle", "cycling", "bike", "biking", "bicycle",
             "spin", "spinning", "peloton", "mtb"],
            unit: "mi")
        add(["swim", "swimming", "laps", "pool",
             "freestyle", "backstroke", "breaststroke", "butterfly"],
            unit: "laps")

        // Duration — minutes
        add(["sleep", "sleeping", "nap", "bedtime", "siesta", "powernap",
             "meditation", "meditate", "yoga", "stretch", "stretching",
             "pilates", "barre", "mobility", "vinyasa", "hatha", "ashtanga",
             "focus", "deep", "pomodoro", "deepwork", "flowstate",
             "study", "studying", "practice", "learn", "learning",
             "coding", "code", "programming", "develop", "development",
             "read", "reading", "book", "podcast", "audiobook",
             "breathwork", "pranayama", "boxbreathing",
             "massage", "sauna", "steam",
             "screentime", "screen",
             "workout", "exercise", "training", "gym",
             "dance", "dancing", "ballet", "salsa", "zumba",
             "music", "piano", "guitar", "instrument",
             "journal", "journaling", "writing", "write",
             "meeting", "meetings", "call", "standup",
             "prayer", "pray", "meditation",
             "outdoor", "outdoors", "sun", "sunshine", "sunlight"],
            unit: "min")

        // Duration — seconds
        add(["deadhang", "hang", "plank", "wallsit",
             "lsit", "handstand", "sprint", "interval"],
            unit: "sec")

        // Duration — hours
        add(["fasting", "fast", "intermittent", "omad",
             "vacation", "travel", "trip"],
            unit: "hr")

        // Volume (US: fluid oz)
        add(["water", "hydrate", "hydration", "drink", "drinking",
             "fluid", "fluids", "liquids", "h2o", "sip",
             "electrolyte", "electrolytes",
             "juice", "smoothie", "shake"],
            unit: "oz")

        // Hot beverages (cups)
        add(["coffee", "tea", "espresso", "latte", "matcha",
             "chai", "americano", "cappuccino", "herbal",
             "greentea", "kombucha", "decaf"],
            unit: "cups")

        // Body weight (US: lbs)
        add(["weight", "weigh", "scale", "bmi", "body",
             "bodyfat", "bodycomp", "lean", "mass",
             "bulking", "cutting", "recomp"],
            unit: "lbs")

        // Lifting weight (US: lbs)
        add(["lift", "lifting", "deadlift", "squat", "bench",
             "barbell", "weights", "dumbbell", "kettlebell",
             "press", "overhead", "curl", "row", "shrug",
             "snatch", "cleanandjerk", "powerlifting"],
            unit: "lbs")

        // Supplements / Nutrition (grams)
        add(["protein", "creatine", "collagen", "supplement", "fiber",
             "carbs", "carbohydrate", "fat", "bcaa", "glutamine",
             "magnesium", "zinc", "calcium", "powder"],
            unit: "gm")

        // Supplement dosage (mg)
        add(["ashwagandha", "turmeric", "melatonin", "iron",
             "b12", "d3", "omega", "fishoil", "probiotic",
             "vitamin", "vitamins", "multivitamin", "capsule", "tablet",
             "ibuprofen", "aspirin", "medicine", "medication", "meds",
             "dose", "dosage"],
            unit: "mg")

        // Reps / Count
        add(["pushup", "pullup", "chinup", "burpee", "crunches", "situp",
             "rep", "reps", "set", "sets", "dips", "lunge", "lunges",
             "muscleup", "calfraise", "hipthrust", "jumpingjack",
             "mountainclimber", "legpress", "pistol"],
            unit: "reps")
        add(["steps", "step"],
            unit: "steps")

        // Pages
        add(["pages", "book", "books", "chapter", "novel",
             "kindle", "ebook", "hardcover", "paperback"],
            unit: "pg")

        // Words (writing)
        add(["wordcount", "essay", "blog", "content",
             "copywriting", "draft", "screenplay", "script"],
            unit: "words")

        // Calories
        add(["calories", "calorie", "cal", "kcal",
             "meal", "meals", "food", "eat", "eating",
             "breakfast", "lunch", "dinner", "snack"],
            unit: "kcal")

        // Currency (US: $)
        add(["money", "budget", "saving", "savings", "spend", "spending",
             "expense", "expenses", "invest", "investing",
             "bill", "bills", "rent", "mortgage", "tax", "taxes",
             "debt", "loan", "income", "salary", "wage",
             "subscription", "payment", "receipt",
             "donation", "donate", "charity"],
            unit: "$")

        // Temperature (US: °F)
        add(["temperature", "temp", "fever", "thermometer",
             "basal", "bbt"],
            unit: "°F")

        // Heart rate
        add(["heartrate", "heart", "pulse", "bpm",
             "resting", "hrv", "zones"],
            unit: "bpm")

        // Blood metrics
        add(["glucose", "sugar", "blood", "pressure",
             "cholesterol", "triglyceride", "a1c"],
            unit: "mg/dL")

        // Oxygen
        add(["spo2", "oxygen", "saturation", "oximeter"],
            unit: "%")

        // Waist / body measurements
        add(["waist", "hip", "circumference", "chest",
             "bicep", "thigh", "calf", "neck"],
            unit: "in")

        return map
    }()

    // MARK: - MetricKind Suggestion

    /// Suggests a MetricKind based on activity name keywords (only relevant for .metric type).
    static func suggestMetricKind(for name: String) -> MetricKind? {
        let words = name.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for word in words {
            if let kind = metricKindKeywordMap[word] {
                return kind
            }
        }
        return nil
    }

    private static let metricKindKeywordMap: [String: MetricKind] = {
        var map = [String: MetricKind]()

        func add(_ keywords: [String], kind: MetricKind) {
            for kw in keywords { map[kw] = kind }
        }

        // Photo — visual progress tracking
        add(["photo", "photos", "selfie", "picture", "pictures",
             "progress", "timelapse", "transformation", "beforeafter",
             "physique", "mirror", "snapshot", "camera"],
            kind: .photo)

        // Value — numeric measurements
        add(["weight", "weigh", "scale", "bmi", "bodyfat", "bodycomp",
             "bloodpressure", "pressure", "glucose", "sugar", "a1c",
             "cholesterol", "heart", "heartrate", "pulse", "bpm", "hrv",
             "temperature", "temp", "fever", "basal",
             "spo2", "oxygen", "saturation",
             "vo2", "vo2max", "lactate",
             "waist", "hip", "circumference", "chest", "bicep", "thigh",
             "testosterone", "estrogen", "cortisol", "thyroid",
             "iron", "ferritin", "hemoglobin",
             "networth", "balance", "score",
             "bodymeasurement", "measurement", "measurements"],
            kind: .value)

        // Checkbox — binary done/not-done milestones
        add(["floss", "sunscreen", "spf", "moisturize",
             "vitamins", "supplement", "pill", "pills", "meds",
             "brush", "mouthwash", "retainer",
             "shower", "bath",
             "cleandesk", "makebed", "bed",
             "laundry", "dishes", "vacuum",
             "inbox", "inboxzero",
             "cold", "coldshower", "coldplunge", "icebath",
             "nosugar", "noalcohol", "nojunkfood", "nofap",
             "alcohol", "sober", "sobriety",
             "gratitude", "grateful", "affirmation",
             "pray", "prayer", "devotional",
             "screen", "phonefree", "nophone",
             "stretch", "stretching", "warmup", "cooldown"],
            kind: .checkbox)

        // Notes — qualitative / text entries
        add(["journal", "journaling", "diary",
             "reflection", "reflect", "review",
             "gratitudelog", "morningpages",
             "dream", "dreams", "dreamlog",
             "therapy", "session", "note", "notes",
             "braindump", "freewrite", "thoughts",
             "mood", "moodlog", "emotion", "emotions",
             "lesson", "insight", "insights", "takeaway",
             "observation", "observations"],
            kind: .notes)

        return map
    }()
}
