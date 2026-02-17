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

        // ── Hydration ──
        add(["water", "hydrate", "hydration", "drink", "drinking", "fluid", "liquids"],
            icon: "drop.fill", color: "#45B7D1")

        // ── Exercise & Fitness ──
        add(["exercise", "workout", "training", "gym", "fitness", "sweat"],
            icon: "figure.run", color: "#FF6B35")
        add(["run", "running", "jog", "jogging", "sprint"],
            icon: "figure.run", color: "#FF6B6B")
        add(["walk", "walking", "steps", "hike", "hiking", "trek"],
            icon: "figure.walk", color: "#00B894")
        add(["cycle", "cycling", "bike", "biking", "bicycle"],
            icon: "bicycle", color: "#4ECDC4")
        add(["swim", "swimming", "pool", "laps"],
            icon: "figure.pool.swim", color: "#74B9FF")
        add(["yoga", "stretch", "stretching", "flexibility", "pilates"],
            icon: "figure.yoga", color: "#A29BFE")
        add(["lift", "lifting", "weights", "strength", "deadlift", "squat", "bench", "barbell"],
            icon: "dumbbell.fill", color: "#E17055")
        add(["pushup", "pullup", "chinup", "burpee", "plank", "crunches", "situp", "abs"],
            icon: "figure.strengthtraining.traditional", color: "#FF6B35")
        add(["cardio", "hiit", "aerobic", "jumping", "jump", "skipping"],
            icon: "heart.circle.fill", color: "#FD79A8")
        add(["climb", "climbing", "boulder", "bouldering"],
            icon: "figure.climbing", color: "#E17055")
        add(["martial", "boxing", "kickboxing", "karate", "taekwondo", "judo", "mma"],
            icon: "figure.martial.arts", color: "#FF6B6B")
        add(["dance", "dancing", "ballet", "salsa"],
            icon: "figure.dance", color: "#FD79A8")
        add(["tennis", "badminton", "squash", "racquet", "paddle"],
            icon: "tennisball.fill", color: "#96CEB4")
        add(["basketball", "football", "soccer", "volleyball", "sports", "game"],
            icon: "sportscourt.fill", color: "#FF6B35")
        add(["golf", "putting"],
            icon: "figure.golf", color: "#96CEB4")
        add(["ski", "skiing", "snowboard", "snowboarding"],
            icon: "figure.skiing.downhill", color: "#74B9FF")
        add(["row", "rowing", "kayak", "canoe"],
            icon: "figure.rowing", color: "#45B7D1")
        add(["deadhang", "hang", "grip"],
            icon: "hand.raised.fill", color: "#E17055")

        // ── Nutrition & Food ──
        add(["eat", "eating", "food", "meal", "meals", "calories", "calorie", "diet"],
            icon: "fork.knife", color: "#FF6B6B")
        add(["cook", "cooking", "recipe", "kitchen", "bake", "baking"],
            icon: "frying.pan.fill", color: "#E17055")
        add(["fruit", "fruits", "vegetable", "vegetables", "veggies", "salad", "greens"],
            icon: "leaf.fill", color: "#00B894")
        add(["protein", "shake", "supplement", "vitamins", "vitamin", "creatine"],
            icon: "pills.fill", color: "#A29BFE")
        add(["coffee", "tea", "caffeine", "espresso", "latte"],
            icon: "cup.and.saucer.fill", color: "#E17055")
        add(["breakfast", "lunch", "dinner", "snack", "supper"],
            icon: "takeoutbag.and.cup.and.straw.fill", color: "#FF6B35")
        add(["fast", "fasting", "intermittent"],
            icon: "clock.badge.xmark", color: "#FFEAA7")
        add(["alcohol", "beer", "wine", "sober", "sobriety"],
            icon: "wineglass.fill", color: "#C44DFF")

        // ── Sleep & Rest ──
        add(["sleep", "sleeping", "bedtime", "bed", "nap"],
            icon: "moon.fill", color: "#A29BFE")
        add(["wake", "wakeup", "alarm", "morning"],
            icon: "sunrise.fill", color: "#FFEAA7")

        // ── Mindfulness & Mental Health ──
        add(["meditate", "meditation", "mindfulness", "mindful", "zen"],
            icon: "brain.head.profile.fill", color: "#A29BFE")
        add(["breathe", "breathing", "breathwork", "pranayama"],
            icon: "wind", color: "#74B9FF")
        add(["journal", "journaling", "diary", "reflect", "reflection"],
            icon: "book.fill", color: "#FFEAA7")
        add(["gratitude", "grateful", "thankful", "affirmation", "affirmations"],
            icon: "heart.fill", color: "#FD79A8")
        add(["therapy", "therapist", "counseling", "mental"],
            icon: "brain.fill", color: "#C44DFF")
        add(["mood", "emotion", "emotions", "feeling", "feelings"],
            icon: "face.smiling.fill", color: "#FFEAA7")
        add(["stress", "relax", "relaxation", "calm", "anxiety"],
            icon: "leaf.fill", color: "#96CEB4")

        // ── Reading & Learning ──
        add(["read", "reading", "book", "books", "pages", "literature"],
            icon: "book.fill", color: "#74B9FF")
        add(["study", "studying", "learn", "learning", "course", "class", "lecture"],
            icon: "graduationcap.fill", color: "#45B7D1")
        add(["language", "vocab", "vocabulary", "duolingo", "flashcard", "flashcards"],
            icon: "character.book.closed.fill", color: "#4ECDC4")
        add(["podcast", "podcasts", "audiobook", "listen"],
            icon: "headphones", color: "#C44DFF")
        add(["news", "newspaper", "article", "articles"],
            icon: "newspaper.fill", color: "#74B9FF")

        // ── Work & Productivity ──
        add(["work", "working", "office", "task", "tasks", "todo"],
            icon: "briefcase.fill", color: "#45B7D1")
        add(["code", "coding", "program", "programming", "develop", "development", "dev"],
            icon: "chevron.left.forwardslash.chevron.right", color: "#4ECDC4")
        add(["email", "emails", "inbox", "mail"],
            icon: "envelope.fill", color: "#74B9FF")
        add(["meeting", "meetings", "call", "standup"],
            icon: "person.2.fill", color: "#A29BFE")
        add(["write", "writing", "blog", "essay", "content"],
            icon: "pencil.line", color: "#FFEAA7")
        add(["plan", "planning", "organize", "review"],
            icon: "list.clipboard.fill", color: "#96CEB4")
        add(["focus", "deep", "pomodoro", "timer"],
            icon: "timer", color: "#FF6B35")
        add(["project", "projects", "milestone"],
            icon: "folder.fill", color: "#45B7D1")

        // ── Self-Care & Hygiene ──
        add(["skincare", "skin", "moisturize", "sunscreen", "spf", "retinol"],
            icon: "drop.circle.fill", color: "#FD79A8")
        add(["shower", "bath", "hygiene", "groom", "grooming"],
            icon: "shower.fill", color: "#74B9FF")
        add(["teeth", "brush", "floss", "dental", "mouthwash"],
            icon: "mouth.fill", color: "#4ECDC4")
        add(["hair", "haircare", "shampoo"],
            icon: "comb.fill", color: "#FD79A8")

        // ── Health & Medical ──
        add(["medicine", "medication", "pills", "prescription", "meds", "drug"],
            icon: "pills.fill", color: "#FF6B6B")
        add(["doctor", "appointment", "checkup", "hospital", "clinic"],
            icon: "cross.case.fill", color: "#FF6B6B")
        add(["weight", "weigh", "scale", "bmi"],
            icon: "scalemass.fill", color: "#E17055")
        add(["blood", "pressure", "glucose", "sugar", "insulin"],
            icon: "heart.text.square.fill", color: "#FF6B6B")
        add(["posture", "ergonomic", "back", "spine"],
            icon: "figure.stand", color: "#96CEB4")
        add(["eye", "eyes", "vision", "eyedrops"],
            icon: "eye.fill", color: "#45B7D1")

        // ── Finance ──
        add(["money", "finance", "budget", "saving", "savings", "invest", "investing"],
            icon: "dollarsign.circle.fill", color: "#00B894")
        add(["spend", "spending", "expense", "expenses", "track"],
            icon: "creditcard.fill", color: "#FF6B35")

        // ── Social & Relationships ──
        add(["family", "kids", "children", "parenting", "parent"],
            icon: "figure.2.and.child.holdinghands", color: "#FD79A8")
        add(["friends", "social", "hang", "hangout", "socialize"],
            icon: "person.3.fill", color: "#A29BFE")
        add(["date", "dating", "partner", "relationship"],
            icon: "heart.circle.fill", color: "#FD79A8")
        add(["phone", "contact", "chat", "text", "message"],
            icon: "phone.fill", color: "#4ECDC4")

        // ── Creative & Hobbies ──
        add(["draw", "drawing", "sketch", "art", "paint", "painting", "illustration"],
            icon: "paintbrush.fill", color: "#C44DFF")
        add(["music", "instrument", "piano", "guitar", "sing", "singing", "practice"],
            icon: "music.note", color: "#FD79A8")
        add(["photo", "photography", "camera", "pictures"],
            icon: "camera.fill", color: "#C44DFF")
        add(["craft", "crafts", "knit", "knitting", "sew", "sewing", "crochet"],
            icon: "scissors", color: "#E17055")
        add(["garden", "gardening", "plants", "plant", "water"],
            icon: "leaf.fill", color: "#00B894")
        add(["game", "gaming", "videogame", "play"],
            icon: "gamecontroller.fill", color: "#A29BFE")

        // ── Home & Chores ──
        add(["clean", "cleaning", "chores", "chore", "tidy", "declutter"],
            icon: "bubbles.and.sparkles.fill", color: "#4ECDC4")
        add(["laundry", "wash", "dishes", "vacuum"],
            icon: "washer.fill", color: "#74B9FF")
        add(["organize", "sort", "arrange"],
            icon: "tray.2.fill", color: "#96CEB4")
        add(["repair", "fix", "maintenance", "maintain"],
            icon: "wrench.and.screwdriver.fill", color: "#E17055")
        add(["grocery", "groceries", "shopping", "shop"],
            icon: "cart.fill", color: "#FF6B35")
        add(["pet", "dog", "cat", "walk"],
            icon: "pawprint.fill", color: "#E17055")

        // ── Spiritual & Religious ──
        add(["pray", "prayer", "prayers", "church", "mosque", "temple", "worship"],
            icon: "hands.and.sparkles.fill", color: "#FFEAA7")
        add(["quran", "bible", "scripture", "dharma", "spiritual"],
            icon: "book.closed.fill", color: "#A29BFE")

        // ── Travel & Outdoors ──
        add(["travel", "trip", "vacation", "explore"],
            icon: "airplane", color: "#45B7D1")
        add(["outdoor", "outdoors", "nature", "park", "forest"],
            icon: "tree.fill", color: "#00B894")
        add(["sun", "sunshine", "sunlight", "daylight", "outside"],
            icon: "sun.max.fill", color: "#FFEAA7")

        // ── Screen Time & Digital ──
        add(["screen", "screentime", "digital", "detox", "unplug"],
            icon: "iphone.slash", color: "#C44DFF")
        add(["social", "media", "instagram", "twitter", "tiktok", "youtube", "reddit"],
            icon: "bubble.left.and.bubble.right.fill", color: "#FD79A8")

        // ── Miscellaneous ──
        add(["habit", "habits", "routine", "daily", "streak"],
            icon: "flame.fill", color: "#FF6B35")
        add(["goal", "goals", "target", "milestone", "achieve"],
            icon: "target", color: "#FF6B6B")
        add(["challenge", "challenge", "dare"],
            icon: "bolt.fill", color: "#FFEAA7")
        add(["log", "logging", "record", "tracking", "measure"],
            icon: "list.bullet.clipboard.fill", color: "#4ECDC4")

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
             "yoga", "stretch", "stretching", "pilates",
             "lift", "lifting", "weights", "strength", "deadlift", "squat", "bench",
             "pushup", "pullup", "chinup", "burpee", "plank", "crunches", "situp",
             "cardio", "hiit", "aerobic", "jumping", "skipping",
             "exercise", "workout", "gym", "fitness", "training",
             "row", "rowing", "deadhang", "hang", "grip",
             "steps", "basketball", "football", "soccer", "tennis", "golf",
             "climb", "climbing", "hike", "hiking", "sprint"],
            category: "Workout")

        // Supplement
        add(["vitamin", "vitamins", "supplement", "supplements",
             "creatine", "protein", "collagen", "probiotic", "omega",
             "magnesium", "zinc", "iron", "calcium", "b12", "d3",
             "fish", "pill", "pills", "capsule", "tablet",
             "ashwagandha", "turmeric", "melatonin"],
            category: "Supplement")

        // Hygiene
        add(["shower", "bath", "brush", "floss", "teeth", "dental",
             "skincare", "skin", "moisturize", "sunscreen", "spf", "retinol",
             "hair", "haircare", "shampoo", "groom", "grooming",
             "hygiene", "wash", "clean", "mouthwash", "deodorant"],
            category: "Hygiene")

        // Medical
        add(["medicine", "medication", "doctor", "appointment",
             "therapy", "therapist", "checkup", "bloodwork", "lab",
             "prescription", "medical", "health", "dentist",
             "blood", "pressure", "glucose", "insulin", "inhaler"],
            category: "Medical")

        // Skills
        add(["read", "reading", "study", "studying", "learn", "learning",
             "course", "class", "practice", "code", "coding", "programming",
             "write", "writing", "journal", "journaling",
             "language", "spanish", "french", "mandarin", "japanese",
             "guitar", "piano", "music", "instrument", "draw", "drawing",
             "paint", "painting", "skill", "skills", "leetcode",
             "book", "books", "podcast", "meditate", "meditation"],
            category: "Skills")

        // Tracking
        add(["weight", "weigh", "measure", "track", "tracking", "log",
             "water", "hydration", "sleep", "calories", "calorie",
             "mood", "energy", "heart", "heartrate", "temperature",
             "bmi", "body", "waist", "steps", "screen", "screentime",
             "budget", "expense", "saving", "savings", "spending"],
            category: "Tracking")

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
             "hike", "hiking", "sprint", "distance",
             "cycle", "cycling", "bike", "biking", "bicycle"],
            unit: "mi")
        add(["swim", "swimming", "laps", "pool"],
            unit: "laps")

        // Duration / Time
        add(["sleep", "sleeping", "nap", "bedtime",
             "meditation", "meditate", "yoga", "stretch", "stretching",
             "focus", "deep", "pomodoro",
             "study", "studying", "practice",
             "coding", "code", "programming",
             "read", "reading"],
            unit: "min")
        add(["deadhang", "hang", "plank"],
            unit: "sec")

        // Volume (US: fluid oz)
        add(["water", "hydrate", "hydration", "drink", "drinking", "fluid", "liquids"],
            unit: "oz")

        // Body weight (US: lbs)
        add(["weight", "weigh", "scale", "bmi", "body"],
            unit: "lbs")

        // Lifting weight (US: lbs)
        add(["lift", "lifting", "deadlift", "squat", "bench", "barbell", "weights"],
            unit: "lbs")

        // Supplements / Nutrition (grams)
        add(["protein", "creatine", "collagen", "supplement", "fiber",
             "carbs", "carbohydrate", "fat"],
            unit: "gm")

        // Reps / Count
        add(["pushup", "pullup", "chinup", "burpee", "crunches", "situp",
             "rep", "reps", "set", "sets"],
            unit: "reps")
        add(["steps", "step"],
            unit: "steps")

        // Pages
        add(["pages", "book", "books"],
            unit: "pg")

        // Calories
        add(["calories", "calorie", "cal", "kcal"],
            unit: "kcal")

        // Currency (US: $)
        add(["money", "budget", "saving", "savings", "spend", "spending",
             "expense", "expenses", "invest", "investing"],
            unit: "$")

        // Temperature (US: °F)
        add(["temperature", "temp", "fever"],
            unit: "°F")

        // Heart rate
        add(["heartrate", "heart", "pulse", "bpm"],
            unit: "bpm")

        // Blood metrics
        add(["glucose", "sugar", "blood", "pressure"],
            unit: "mg/dL")

        return map
    }()
}
