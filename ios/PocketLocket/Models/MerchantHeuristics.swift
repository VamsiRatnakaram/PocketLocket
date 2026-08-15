import Foundation

/// Built-in merchant → category guesses so auto-categorization feels smart out
/// of the box. Applied after user rules and before any provider category.
/// Phrases are matched on complete descriptor tokens, so `rent` cannot match a
/// merchant such as "Brent's Bistro". More specific / higher-priority entries
/// are listed first.
enum MerchantHeuristics {
    static let table: [(keyword: String, category: SpendCategory)] = [
        // 1) Transfers, card payments & investments — NEVER counted as spend.
        //    Listed first so, with several accounts linked, moving money between
        //    them (or paying a card) doesn't inflate the spending ring.
        // Bare "autopay"/"auto pay" and "mobile payment" are not card-payment
        // evidence: Netflix, Verizon, Geico and every other biller use them
        // too, and reading those as transfers erased real spending from the
        // budget entirely. They now need card context.
        ("payment thank you", .transfer), ("card autopay", .transfer), ("crd autopay", .transfer),
        ("discover autopay", .transfer), ("amex autopay", .transfer), ("citi autopay", .transfer),
        ("capital one autopay", .transfer),
        ("online payment", .transfer), ("bill pay", .transfer),
        ("credit card payment", .transfer), ("card payment", .transfer), ("e-payment", .transfer),
        ("epayment", .transfer),
        ("ach payment", .transfer), ("ach pmt", .transfer),
        ("ach debit", .transfer), ("ach credit", .transfer), ("web pmt", .transfer),
        ("online transfer", .transfer), ("internal transfer", .transfer), ("funds transfer", .transfer),
        ("wire transfer", .transfer), ("bank transfer", .transfer), ("transfer to", .transfer),
        ("transfer from", .transfer), ("xfer", .transfer), ("withdrawal", .transfer),
        ("atm withdrawal", .transfer), ("to savings", .transfer), ("from savings", .transfer),
        ("robinhood", .transfer), ("coinbase", .transfer), ("fidelity", .transfer),
        ("vanguard", .transfer), ("charles schwab", .transfer), ("wealthfront", .transfer),
        ("betterment", .transfer), ("acorns", .transfer), ("brokerage", .transfer),
        ("401k", .transfer), ("roth ira", .transfer),

        // 1b) Credit card issuers paying off a card from a linked bank account
        //     use their own short-form descriptors (e.g. "CAPITAL ONE MOBILE
        //     PYMT", "CHASE CREDIT CRD AUTOPAY", "DISCOVER E-PAYMENT"). These
        //     move money between two of the user's own accounts and would
        //     otherwise double-count as spend on top of the card's own
        //     transactions for the same purchases.
        //     Matching is over contiguous whole tokens, so "cc pymt" cannot
        //     reach the "mobile pymt" in Capital One's descriptor and the two
        //     abbreviations each need their own entry. "pymt" and "e payment"
        //     are abbreviations banks only use for card payments, and token
        //     matching stops "mobile pymt" from touching "T-Mobile payment".
        ("chase credit crd", .transfer), ("cc payment", .transfer), ("cc pymt", .transfer),
        //     Deliberately not "autopay": Netflix, Verizon and every other
        //     biller use it too, and misreading those as transfers would erase
        //     real spending from the budget.
        ("payment to crd", .transfer), ("mobile pymt", .transfer),
        ("e payment", .transfer), ("online pymt", .transfer),

        // 2) Income (inflows).
        ("payroll", .income), ("paycheck", .income), ("direct deposit", .income),
        ("direct dep", .income), ("salary", .income), ("dividend", .income),
        ("interest paid", .income), ("tax refund", .income), ("irs treas", .income),
        ("reimbursement", .income),

        // 3) Specific multi-word merchants (before the generic keywords below).
        ("uber eats", .food), ("amazon prime", .services), ("amazon fresh", .groceries),
        ("apple store", .shopping), ("apple.com/bill", .services), ("apple music", .entertainment),
        ("google one", .services), ("microsoft 365", .services), ("whole foods", .groceries),
        ("wholefoods", .groceries), ("trader joe", .groceries), ("traderjoes", .groceries),
        ("sam's club", .shopping), ("in-n-out", .food), ("in n out", .food),
        ("chick-fil", .food), ("five guys", .food), ("shake shack", .food),
        ("panda express", .food), ("raising cane", .food), ("jersey mike", .food),
        ("jimmy john", .food), ("taco bell", .food), ("burger king", .food),
        ("pizza hut", .food), ("papa john", .food), ("little caesar", .food),
        ("olive garden", .food), ("cheesecake factory", .food), ("buffalo wild", .food),
        ("texas roadhouse", .food), ("dave & buster", .entertainment), ("home depot", .housing),
        ("best buy", .shopping), ("bed bath", .shopping), ("bath & body", .shopping),
        ("dick's sporting", .shopping), ("old navy", .shopping), ("banana republic", .shopping),
        ("hobby lobby", .shopping), ("office depot", .shopping), ("dollar general", .shopping),
        ("dollar tree", .shopping), ("family dollar", .shopping), ("five below", .shopping),
        ("rite aid", .health), ("urgent care", .health), ("one medical", .health),
        ("quest diagnostics", .health), ("warby parker", .health), ("planet fitness", .services),
        ("24 hour fitness", .services), ("la fitness", .services), ("ups store", .services),
        ("national grid", .housing), ("duke energy", .housing), ("con edison", .housing),
        ("waste management", .housing), ("student loan", .fees), ("annual fee", .fees),
        ("late fee", .fees), ("interest charge", .fees), ("finance charge", .fees),
        ("overdraft fee", .fees), ("foreign transaction fee", .fees),

        // 4) Entertainment / streaming.
        ("netflix", .entertainment), ("spotify", .entertainment), ("hulu", .entertainment),
        ("disney", .entertainment), ("hbo", .entertainment), ("youtube", .entertainment),
        ("peacock", .entertainment), ("paramount", .entertainment), ("crunchyroll", .entertainment),
        ("twitch", .entertainment), ("steam", .entertainment), ("playstation", .entertainment),
        ("xbox", .entertainment), ("nintendo", .entertainment), ("epic games", .entertainment),
        ("roblox", .entertainment), ("fandango", .entertainment), ("ticketmaster", .entertainment),
        ("stubhub", .entertainment), ("live nation", .entertainment), ("amc", .entertainment),
        ("regal", .entertainment), ("cinemark", .entertainment), ("cinema", .entertainment),
        ("audible", .entertainment),

        // 5) Transport / fuel / auto.
        ("uber", .transport), ("lyft", .transport), ("waymo", .transport), ("shell", .transport),
        ("chevron", .transport), ("exxon", .transport), ("arco", .transport), ("valero", .transport),
        ("sunoco", .transport), ("speedway", .transport), ("circle k", .transport),
        ("quiktrip", .transport), ("gas station", .transport), ("parking", .transport),
        ("garage", .transport), ("toll", .transport), ("fastrak", .transport), ("e-zpass", .transport),
        ("ezpass", .transport), ("mta", .transport), ("bart", .transport), ("caltrain", .transport),
        ("transit", .transport), ("autozone", .transport), ("o'reilly", .transport),
        ("wsf", .transport), ("wsdot", .transport), ("wa state ferries", .transport),
        ("washington state ferries", .transport),
        ("jiffy lube", .transport), ("car wash", .transport),
        ("aaa", .transport),
        ("citgo", .transport), ("phillips 66", .transport),
        ("conoco", .transport), ("costco gas", .transport),
        ("roadside assistance", .transport), ("towing", .transport),

        // Shared scooters and bikes. "lime" and "spin" are also ordinary
        // words, so the restaurant names that contain them are listed first —
        // the table is first-match-wins over contiguous tokens.
        ("lime leaf", .food), ("lime fresh", .food), ("key lime", .food),
        ("spin pizza", .food), ("bird dog", .food),
        ("lime", .transport), ("limebike", .transport), ("bird rides", .transport),
        ("bird app", .transport), ("veo ride", .transport), ("citi bike", .transport),
        ("citibike", .transport), ("divvy", .transport), ("bluebikes", .transport),
        ("bay wheels", .transport), ("scooter", .transport),

        // 6) Travel.
        ("delta", .travel), ("united air", .travel), ("american air", .travel),
        ("southwest", .travel), ("jetblue", .travel), ("alaska air", .travel),
        ("frontier", .travel), ("spirit air", .travel), ("airbnb", .travel), ("vrbo", .travel),
        ("marriott", .travel), ("hilton", .travel), ("hyatt", .travel), ("sheraton", .travel),
        ("holiday inn", .travel), ("best western", .travel), ("expedia", .travel),
        ("booking.com", .travel), ("priceline", .travel), ("hotel", .travel), ("resort", .travel),
        ("hertz", .travel), ("avis", .travel), ("enterprise rent", .travel), ("turo", .travel),
        ("airport", .travel),

        // 7) Food & dining.
        ("starbucks", .food), ("dunkin", .food), ("peet's", .food), ("dutch bros", .food),
        ("mcdonald", .food), ("mcdonalds", .food), ("wendy", .food), ("chipotle", .food), ("popeyes", .food),
        ("subway", .food), ("domino", .food), ("sweetgreen", .food), ("panera", .food),
        ("whataburger", .food), ("culver", .food), ("denny", .food), ("ihop", .food),
        ("applebee", .food), ("chili's", .food), ("outback", .food), ("red lobster", .food),
        ("doordash", .food), ("grubhub", .food), ("postmates", .food), ("7-eleven", .food),
        ("wawa", .food), ("sheetz", .food), ("instacart", .groceries),
        ("safeway", .groceries), ("kroger", .groceries), ("publix", .groceries), ("aldi", .groceries),
        ("wegmans", .groceries), ("sprouts", .groceries), ("food lion", .groceries), ("albertsons", .groceries),
        ("ralphs", .groceries), ("h-e-b", .groceries), ("h mart", .groceries), ("winco", .groceries),
        ("meijer", .groceries), ("lidl", .groceries), ("giant eagle", .groceries),
        ("market basket", .groceries), ("shoprite", .groceries), ("hannaford", .groceries),
        ("piggly wiggly", .groceries), ("stater bros", .groceries), ("smart final", .groceries),
        ("win dixie", .groceries), ("grocery", .groceries),
        ("restaurant", .food), ("grill", .food), ("grille", .food), ("bistro", .food), ("bar", .food),
        ("pub", .food), ("tavern", .food), ("eatery", .food), ("kitchen", .food),
        ("cantina", .food), ("diner", .food), ("steakhouse", .food), ("bbq", .food),
        ("brewery", .food), ("coffee", .food), ("cafe", .food), ("pizzeria", .food),
        ("sushi", .food), ("taqueria", .food), ("bakery", .food), ("pizza", .food),
        ("deli", .food), ("burrito", .food), ("taco", .food), ("poke", .food),
        ("boba", .food), ("bubble tea", .food), ("teahouse", .food), ("tea house", .food),
        ("chophouse", .food), ("seafood", .food), ("buffet", .food), ("smokehouse", .food),
        ("creamery", .food), ("donut", .food), ("doughnut", .food), ("bagel", .food),
        ("sandwich", .food), ("hibachi", .food), ("teriyaki", .food), ("curry", .food),
        ("izakaya", .food), ("gastropub", .food), ("brasserie", .food),
        ("trattoria", .food), ("espresso", .food), ("noodle", .food), ("dumpling", .food),
        ("burger", .food),

        // 8) Shopping / retail.
        ("amazon", .shopping), ("target", .shopping), ("walmart", .shopping), ("costco", .shopping),
        ("ebay", .shopping), ("etsy", .shopping), ("aliexpress", .shopping), ("shein", .shopping),
        ("temu", .shopping), ("wayfair", .shopping), ("gamestop", .shopping), ("newegg", .shopping),
        ("lowe's", .housing), ("ace hardware", .housing), ("macy", .shopping), ("nordstrom", .shopping),
        ("kohl", .shopping), ("tj maxx", .shopping), ("marshalls", .shopping), ("nike", .shopping),
        ("adidas", .shopping), ("lululemon", .shopping), ("uniqlo", .shopping), ("sephora", .shopping),
        ("ulta", .shopping), ("michaels", .shopping), ("staples", .shopping), ("ikea", .shopping),
        ("petco", .shopping), ("petsmart", .shopping), ("chewy", .shopping), ("burlington", .shopping),

        // 9) Health / pharmacy.
        ("cvs", .health), ("walgreens", .health), ("pharmacy", .health), ("clinic", .health),
        ("dental", .health), ("dentist", .health), ("kaiser", .health), ("labcorp", .health),
        ("hospital", .health), ("optometry", .health), ("lenscrafters", .health), ("gnc", .health),
        ("surgeon", .health), ("surgeons", .health), ("surgery", .health), ("surgical", .health),

        // 10) Services / subscriptions.
        ("equinox", .services), ("gym", .services), ("adobe", .services), ("dropbox", .services),
        ("icloud", .services), ("membership", .services), ("openai", .services), ("chatgpt", .services),
        ("github", .services), ("godaddy", .services), ("squarespace", .services), ("zoom", .services),
        ("linkedin", .services), ("canva", .services), ("patreon", .services), ("notion", .services),
        ("1password", .services), ("nordvpn", .services), ("salon", .services), ("barber", .services),
        ("laundry", .services), ("dry clean", .services), ("fedex", .services), ("usps", .services),
        ("geico", .services), ("state farm", .services), ("progressive", .services),
        ("allstate", .services), ("insurance", .services), ("storage", .services),

        // 11) Housing / rent.
        ("budget rent", .travel), ("dollar rent", .travel), ("alamo rent", .travel),
        ("bilt rent", .housing),
        ("rent", .housing), ("mortgage", .housing), ("apartment", .housing),

        // 11b) Utilities (electric/gas/water/internet/wifi) — folded into
        // Housing & Bills alongside rent/mortgage.
        ("comcast", .housing), ("xfinity", .housing), ("verizon", .housing),
        ("t-mobile", .housing), ("tmobile", .housing), ("att", .housing), ("spectrum", .housing),
        ("centurylink", .housing), ("dish network", .housing), ("directv", .housing),
        ("pg&e", .housing), ("coned", .housing), ("electric", .housing),
        ("utility", .housing), ("utilities", .housing),
        ("sewer", .housing), ("internet", .housing), ("wifi", .housing),
        ("astound", .housing), ("webpass", .housing), ("google webpass", .housing),
        ("google fiber", .housing),
        ("seattle city light", .housing), ("puget sound energy", .housing),

        // 12) Fees & loans.
        ("sofi", .fees), ("navient", .fees), ("nelnet", .fees), ("affirm", .fees),
        ("klarna", .fees), ("afterpay", .fees), ("auto loan", .fees), ("bank fee", .fees),

        // 13) Chase-branded travel portal / points redemptions.
        ("chase travel", .travel),
    ]

    // High-confidence terms that are intentionally considered after the legacy
    // table. This lets precise bank-transfer and well-known merchant rules win
    // before a broader sector or long-tail merchant match.
    private static let extendedTable: [(keyword: String, category: SpendCategory)] = [
        // Food & groceries.
        ("jamba juice", .food), ("smoothie king", .food), ("cold stone", .food),
        ("baskin robbins", .food), ("crumbl", .food), ("insomnia cookies", .food),
        ("dairy queen", .food), ("wingstop", .food), ("kfc", .food), ("arby", .food),
        ("sonic drive", .food), ("zaxby", .food), ("qdoba", .food), ("moe s southwest", .food),
        ("noodles company", .food), ("pf chang", .food), ("cava", .food),
        ("food hall", .food), ("food truck", .food), ("juice bar", .food),
        ("ice cream", .food), ("gelato", .food), ("ramen", .food), ("pho", .food),
        ("fried chicken", .food), ("wings", .food),
        ("hello fresh", .groceries), ("hellofresh", .groceries), ("everyplate", .groceries),
        ("home chef", .groceries), ("factor meals", .groceries), ("butcherbox", .groceries),
        ("thrive market", .groceries), ("misfits market", .groceries), ("99 ranch", .groceries),
        ("fresh thyme", .groceries), ("natural grocers", .groceries), ("harris teeter", .groceries),
        ("vons", .groceries), ("giant food", .groceries), ("acme markets", .groceries),
        ("supermarket", .groceries), ("farmers market", .groceries), ("meat market", .groceries),
        ("produce market", .groceries),

        // Retail.
        ("rei", .shopping), ("patagonia", .shopping), ("the north face", .shopping),
        ("arc'teryx", .shopping), ("barnes and noble", .shopping), ("barnes & noble", .shopping),
        ("office max", .shopping), ("homegoods", .shopping), ("ross dress", .shopping),
        ("joann fabrics", .shopping), ("lego", .shopping), ("groupon", .shopping),
        ("department store", .shopping), ("sporting goods", .shopping), ("office supplies", .shopping),
        ("pet supplies", .shopping), ("jewelry", .shopping), ("jewellery", .shopping),

        // Housing and utilities.
        ("dominion energy", .housing), ("xcel energy", .housing), ("pseg", .housing),
        ("eversource", .housing), ("firstenergy", .housing), ("georgia power", .housing),
        ("florida power", .housing), ("astound broadband", .housing), ("cox communications", .housing),
        ("rentcafe", .housing), ("appfolio", .housing), ("buildium", .housing),
        ("adt security", .housing), ("vivint", .housing), ("property management", .housing),
        ("homeowners association", .housing), ("hoa payment", .housing), ("condo fee", .housing),
        ("lease payment", .housing), ("rent payment", .housing), ("mortgage payment", .housing),
        ("electric bill", .housing), ("water utility", .housing), ("trash service", .housing),
        ("home security", .housing),

        // Transport and travel.
        ("bp", .transport), ("mobil", .transport), ("marathon", .transport), ("murphy usa", .transport),
        ("racetrac", .transport), ("love's travel", .transport), ("citi bike", .transport),
        ("zipcar", .transport), ("chargepoint", .transport), ("electrify america", .transport),
        ("evgo", .transport), ("parkwhiz", .transport), ("spothero", .transport),
        ("discount tire", .transport), ("firestone", .transport), ("midas", .transport),
        ("valvoline", .transport), ("ev charging", .transport), ("charging station", .transport),
        ("oil change", .transport), ("auto repair", .transport), ("tire service", .transport),
        ("allegiant", .travel), ("sun country", .travel), ("four seasons", .travel),
        ("ritz carlton", .travel), ("westin", .travel), ("courtyard", .travel),
        ("hampton inn", .travel), ("residence inn", .travel), ("motel 6", .travel),
        ("la quinta", .travel), ("wyndham", .travel), ("carnival cruise", .travel),
        ("norwegian cruise", .travel), ("thrifty car", .travel), ("sixt", .travel),
        ("lodging", .travel), ("vacation rental", .travel), ("rental car", .travel),

        // Entertainment and health.
        ("seatgeek", .entertainment), ("tickpick", .entertainment), ("vivid seats", .entertainment),
        ("eventbrite", .entertainment), ("topgolf", .entertainment), ("bowlero", .entertainment),
        ("movie theater", .entertainment), ("live music", .entertainment), ("concert tickets", .entertainment),
        ("art museum", .entertainment),
        ("betterhelp", .health), ("talkspace", .health), ("teladoc", .health), ("mdlive", .health),
        ("doctor on demand", .health), ("headspace", .health), ("calm app", .health),
        ("invisalign", .health), ("physical therapy", .health), ("mental health", .health),
        ("health clinic", .health), ("medical center", .health), ("vision care", .health),
        ("prescription", .health),

        // Professional, home, and digital services.
        ("turbotax", .services), ("h&r block", .services), ("taxact", .services),
        ("legalzoom", .services), ("roto rooter", .services), ("mr rooter", .services),
        ("taskrabbit", .services), ("molly maid", .services), ("the maids", .services),
        ("handy", .services), ("rover", .services), ("pet grooming", .services),
        ("dog grooming", .services), ("wix", .services), ("webflow", .services),
        ("shopify", .services), ("mailchimp", .services), ("constant contact", .services),
        ("expressvpn", .services), ("surfshark", .services), ("bitwarden", .services),
        ("lastpass", .services), ("liberty mutual", .services), ("lemonade insurance", .services),
        ("plumbing", .services), ("electrician", .services), ("hvac", .services),
        ("locksmith", .services), ("house cleaning", .services), ("web hosting", .services),
        ("tax preparation", .services),

        // Fees, credit, and loans.
        ("sezzle", .fees), ("splitit", .fees), ("paypal pay later", .fees),
        ("fedloan", .fees), ("mohela", .fees), ("earnest", .fees), ("lendingclub", .fees),
        ("lending club", .fees), ("upstart", .fees), ("prosper", .fees), ("equifax", .fees),
        ("experian", .fees), ("transunion", .fees), ("lifelock", .fees), ("identityguard", .fees),
        ("identity guard", .fees), ("credit report", .fees), ("identity protection", .fees),
        ("payment plan", .fees), ("installment", .fees),
    ]

    private static let tokenizedTable = (MerchantHeuristics.table + MerchantHeuristics.extendedTable).map { entry in
        (tokens: MerchantHeuristics.tokens(in: entry.keyword), category: entry.category)
    }

    private static let descriptorPrefixes: [[String]] = [
        ["debit", "card", "purchase"], ["card", "purchase"], ["checkcard"], ["pos"],
        ["sq"], ["tst"], ["paypal"], ["pp"], ["stripe"], ["clover"],
    ]

    /// Brands that only ever appear as a processor descriptor of the form
    /// `BRAND*<reference>`, where the reference is a per-ride or per-order id.
    ///
    /// Lime bills as LIME*RIDE, LIME*3XKQ2, LIME*ABC123 — so a keyword entry
    /// like "lime ride" catches exactly one variant and misses every other one.
    ///
    /// Matching the bare token instead would be worse, not better: "lime" also
    /// shows up in restaurant names (LIME LEAF THAI), which would then be
    /// categorized as transport. Keying on the `*` form is what separates the
    /// two, so this is checked against the raw descriptor before tokenizing
    /// drops the punctuation.
    private static let starredBrands: [String: SpendCategory] = [
        "lime": .transport
    ]

    /// The token immediately before the first `*`, matched against the brands
    /// above. Returns nil for processors like `PAYPAL *NETFLIX.COM`, which are
    /// intentionally not listed: the brand there is the payment rail, not the
    /// merchant, so resolution should fall through to the keyword table.
    static func starredBrandCategory(in descriptor: String) -> SpendCategory? {
        guard let star = descriptor.firstIndex(of: "*") else { return nil }
        guard let brand = tokens(in: String(descriptor[descriptor.startIndex..<star])).last else { return nil }
        return starredBrands[brand]
    }

    private static let processorFallbacks: [(tokens: [String], category: SpendCategory)] = [
        // Toast is dedicated to restaurants, unlike Square, PayPal, and Stripe.
        (["tst"], .food), (["toast"], .food),
    ]

    // Memoize lookups: the same merchant strings recur across many transactions
    // and across every view re-render, so caching keeps categorization O(1) on
    // repeat and removes the recompute lag when rules or data change.
    private enum CachedCategory {
        case match(SpendCategory)
        case unmatched
    }

    private static let cacheLock = NSLock()
    private static var cache: [String: CachedCategory] = [:]

    static func normalized(_ value: String) -> String {
        tokens(in: value).joined()
    }

    /// A reusable key for a merchant-specific user rule. It removes known
    /// payment-processor prefixes and trailing store/terminal identifiers while
    /// keeping the meaningful merchant tokens intact.
    static func ruleMatchText(for descriptor: String) -> String {
        var tokens = tokens(in: descriptor)
        while let prefix = descriptorPrefixes.first(where: { tokens.starts(with: $0) }) {
            tokens.removeFirst(prefix.count)
        }
        while let last = tokens.last, last.allSatisfy(\.isNumber) {
            tokens.removeLast()
        }
        return tokens.joined(separator: " ")
    }

    static func matches(_ phrase: String, in descriptor: String) -> Bool {
        contains(tokens(in: phrase), in: tokens(in: descriptor))
    }

    static func tokens(in value: String) -> [String] {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var tokenized = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "&" {
                tokenized.unicodeScalars.append(scalar)
            } else if scalar == "'" || scalar == "’" {
                continue
            } else {
                tokenized.append(" ")
            }
        }
        return tokenized.split(whereSeparator: \ .isWhitespace).map(String.init)
    }

    static func contains(_ phrase: [String], in descriptor: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= descriptor.count else { return false }
        if descriptor.contains(phrase.joined()) { return true }
        for start in 0...(descriptor.count - phrase.count) {
            let candidate = descriptor[start..<(start + phrase.count)]
            if zip(phrase, candidate).allSatisfy({ tokensMatch($0, $1) }) {
                return true
            }
        }
        return false
    }

    private static func tokensMatch(_ phrase: String, _ descriptor: String) -> Bool {
        phrase == descriptor || phrase + "s" == descriptor || phrase == descriptor + "s"
    }

    private static func category(forTokens tokens: [String]) -> SpendCategory? {
        var match: SpendCategory?
        for entry in tokenizedTable where contains(entry.tokens, in: tokens) {
            match = entry.category
            break
        }
        if match == nil {
            for fallback in processorFallbacks where contains(fallback.tokens, in: tokens) {
                match = fallback.category
                break
            }
        }
        // A peer-to-peer rail only decides the category when nothing else in
        // the descriptor did. "PAYPAL *NETFLIX.COM" names a real merchant and
        // keeps it; "VENMO PAYMENT ACH DEBIT" names none, so the rail words
        // must not be allowed to make it a transfer.
        if PeerToPeerPayments.isPlatform(tokens: tokens), match == nil || match == .transfer {
            return PeerToPeerPayments.category(forTokens: tokens)
        }
        return match
    }

    /// Peer-to-peer payment apps, where the descriptor names the platform but
    /// says nothing about what the money was for.
    ///
    /// These are classified as transfers by default, which is right for
    /// repaying a friend and wrong for covering your half of dinner — and the
    /// same descriptor produces both. Callers use this to default a category
    /// choice to "this transaction only", because a merchant-wide rule keyed on
    /// "venmo" would be a guess applied to every past and future Venmo.
    static let peerToPeerKeywords = ["venmo", "zelle", "cash app", "cashapp", "paypal", "apple cash"]

    static func isPeerToPeer(_ descriptor: String) -> Bool {
        let descriptorTokens = tokens(in: descriptor)
        return peerToPeerKeywords.contains { contains(tokens(in: $0), in: descriptorTokens) }
    }

    /// Thread-safe: category resolution now also runs on a background executor
    /// for the Analysis tab while the main thread may be resolving categories
    /// for other views, so the memo table must be locked.
    static func category(for haystack: String) -> SpendCategory? {
        if let starred = starredBrandCategory(in: haystack) { return starred }
        let cacheKey = normalized(haystack)
        cacheLock.lock()
        let cached = cache[cacheKey]
        cacheLock.unlock()
        if let cached {
            switch cached {
            case let .match(category): return category
            case .unmatched: return nil
            }
        }
        let match = category(forTokens: tokens(in: haystack))
    cacheLock.lock()
        cache[cacheKey] = match.map(CachedCategory.match) ?? .unmatched
        cacheLock.unlock()
        return match
    }

    /// Merchants that typically represent recurring subscriptions.
    static let subscriptionKeywords: [String] = [
        "netflix", "spotify", "hulu", "disney", "hbo", "youtube premium", "apple music",
        "icloud", "dropbox", "adobe", "gym", "equinox", "planet fitness", "membership",
        "prime", "patreon", "substack", "notion", "1password",
    ]

    static func isLikelySubscription(_ haystack: String) -> Bool {
        subscriptionKeywords.contains { matches($0, in: haystack) }
    }
}
