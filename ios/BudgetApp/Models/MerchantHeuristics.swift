import Foundation

/// Built-in merchant → category guesses so auto-categorization feels smart out
/// of the box. Applied after user rules and before any provider category.
/// Keywords are matched (lowercased, first match wins) against "merchant + name",
/// so more specific / higher-priority entries are listed first.
enum MerchantHeuristics {
    static let table: [(keyword: String, category: SpendCategory)] = [
        // 1) Transfers, card payments & investments — NEVER counted as spend.
        //    Listed first so, with several accounts linked, moving money between
        //    them (or paying a card) doesn't inflate the spending ring.
        ("payment thank you", .transfer), ("autopay", .transfer), ("auto pay", .transfer),
        ("online payment", .transfer), ("mobile payment", .transfer), ("bill pay", .transfer),
        ("credit card payment", .transfer), ("card payment", .transfer), ("e-payment", .transfer),
        ("epayment", .transfer), ("ach payment", .transfer), ("ach pmt", .transfer),
        ("ach debit", .transfer), ("ach credit", .transfer), ("web pmt", .transfer),
        ("online transfer", .transfer), ("internal transfer", .transfer), ("funds transfer", .transfer),
        ("wire transfer", .transfer), ("bank transfer", .transfer), ("transfer to", .transfer),
        ("transfer from", .transfer), ("xfer", .transfer), ("zelle", .transfer), ("venmo", .transfer),
        ("cash app", .transfer), ("cashapp", .transfer), ("withdrawal", .transfer),
        ("atm withdrawal", .transfer), ("to savings", .transfer), ("from savings", .transfer),
        ("robinhood", .transfer), ("coinbase", .transfer), ("fidelity", .transfer),
        ("vanguard", .transfer), ("charles schwab", .transfer), ("wealthfront", .transfer),
        ("betterment", .transfer), ("acorns", .transfer), ("brokerage", .transfer),
        ("401k", .transfer), ("roth ira", .transfer),

        // 2) Income (inflows).
        ("payroll", .income), ("paycheck", .income), ("direct deposit", .income),
        ("direct dep", .income), ("salary", .income), ("dividend", .income),
        ("interest paid", .income), ("tax refund", .income), ("irs treas", .income),
        ("reimbursement", .income),

        // 3) Specific multi-word merchants (before the generic keywords below).
        ("uber eats", .food), ("amazon prime", .services), ("amazon fresh", .groceries),
        ("apple store", .shopping), ("apple.com/bill", .services), ("apple music", .entertainment),
        ("google one", .services), ("microsoft 365", .services), ("whole foods", .groceries),
        ("trader joe", .groceries), ("sam's club", .shopping), ("in-n-out", .food),
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
        ("jiffy lube", .transport), ("car wash", .transport),

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
        ("mcdonald", .food), ("wendy", .food), ("chipotle", .food), ("popeyes", .food),
        ("subway", .food), ("domino", .food), ("sweetgreen", .food), ("panera", .food),
        ("whataburger", .food), ("culver", .food), ("denny", .food), ("ihop", .food),
        ("applebee", .food), ("chili's", .food), ("outback", .food), ("red lobster", .food),
        ("doordash", .food), ("grubhub", .food), ("postmates", .food), ("instacart", .groceries),
        ("safeway", .groceries), ("kroger", .groceries), ("publix", .groceries), ("aldi", .groceries),
        ("wegmans", .groceries), ("sprouts", .groceries), ("food lion", .groceries), ("albertsons", .groceries),
        ("ralphs", .groceries), ("h-e-b", .groceries), ("grocery", .groceries), ("restaurant", .food),
        ("coffee", .food), ("cafe", .food), ("pizzeria", .food), ("sushi", .food),
        ("taqueria", .food), ("bakery", .food),

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

        // 10) Services / subscriptions.
        ("equinox", .services), ("gym", .services), ("adobe", .services), ("dropbox", .services),
        ("icloud", .services), ("membership", .services), ("openai", .services), ("chatgpt", .services),
        ("github", .services), ("godaddy", .services), ("squarespace", .services), ("zoom", .services),
        ("linkedin", .services), ("canva", .services), ("patreon", .services), ("notion", .services),
        ("1password", .services), ("nordvpn", .services), ("salon", .services), ("barber", .services),
        ("laundry", .services), ("dry clean", .services), ("fedex", .services), ("usps", .services),
        ("geico", .services), ("state farm", .services), ("progressive", .services),
        ("allstate", .services), ("insurance", .services), ("storage", .services),

        // 11) Housing / utilities.
        ("comcast", .housing), ("xfinity", .housing), ("verizon", .housing), ("t-mobile", .housing),
        ("at&t", .housing), ("spectrum", .housing), ("centurylink", .housing), ("dish network", .housing),
        ("directv", .housing), ("pg&e", .housing), ("coned", .housing), ("electric", .housing),
        ("utility", .housing), ("water bill", .housing), ("sewer", .housing), ("internet", .housing),
        ("rent", .housing), ("mortgage", .housing), ("apartment", .housing),

        // 12) Fees & loans.
        ("sofi", .fees), ("navient", .fees), ("nelnet", .fees), ("affirm", .fees),
        ("klarna", .fees), ("afterpay", .fees), ("auto loan", .fees), ("bank fee", .fees),
    ]

    // Memoize lookups: the same merchant strings recur across many transactions
    // and across every view re-render, so caching keeps categorization O(1) on
    // repeat and removes the recompute lag when rules or data change.
    private static var cache: [String: SpendCategory?] = [:]

    static func category(for haystack: String) -> SpendCategory? {
        let h = haystack.lowercased()
        if let cached = cache[h] { return cached }
        var match: SpendCategory?
        for entry in table where h.contains(entry.keyword) {
            match = entry.category
            break
        }
        cache[h] = match
        return match
    }

    /// Merchants that typically represent recurring subscriptions.
    static let subscriptionKeywords: [String] = [
        "netflix", "spotify", "hulu", "disney", "hbo", "youtube premium", "apple music",
        "icloud", "dropbox", "adobe", "gym", "equinox", "planet fitness", "membership",
        "prime", "patreon", "substack", "notion", "1password",
    ]

    static func isLikelySubscription(_ haystack: String) -> Bool {
        let h = haystack.lowercased()
        return subscriptionKeywords.contains { h.contains($0) }
    }
}
