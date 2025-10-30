import Foundation

struct WebSearchResult: Codable, Equatable, Identifiable {
    var id: String { url }
    var title: String
    var url: String
    var snippet: String
    var source: String
}

protocol WebSearching {
    func search(query: String, maxResults: Int) async throws -> [WebSearchResult]
}

// MARK: - Multi-Source Web Search Service
// Aggregates results from DuckDuckGo (priority), Reddit, and Wikipedia
// Privacy-friendly, no API keys required, returns diverse, structured results

final class WebSearchService: WebSearching {
    static let shared = WebSearchService()
    private init() {}

    enum SearchError: Error { case noResults }
    
    private(set) var lastSearchResults: [WebSearchResult] = []

    /// Searches across DuckDuckGo, Reddit, and Wikipedia, prioritizing DuckDuckGo
    func search(query: String, maxResults: Int = 5) async throws -> [WebSearchResult] {
        print("🔍 WebSearch: Starting multi-source search for '\(query)'")
        
        var allResults: [WebSearchResult] = []
        
        // Priority 1: DuckDuckGo (most relevant, fast)
        async let ddgTask = searchDuckDuckGo(query: query, maxResults: maxResults)
        
        // Priority 2: Reddit (community insights)
        async let redditTask = searchReddit(query: query, maxResults: max(2, maxResults / 2))
        
        // Priority 3: Wikipedia (encyclopedic knowledge)
        async let wikiTask = searchWikipedia(query: query, maxResults: max(1, maxResults / 3))
        
        // Gather all results concurrently
        let (ddgResults, redditResults, wikiResults) = await (ddgTask, redditTask, wikiTask)
        
        // Combine with DuckDuckGo prioritized first
        allResults.append(contentsOf: ddgResults)
        allResults.append(contentsOf: redditResults)
        allResults.append(contentsOf: wikiResults)
        
        // Remove duplicates by URL
        var seen = Set<String>()
        let uniqueResults = allResults.filter { result in
            guard !seen.contains(result.url) else { return false }
            seen.insert(result.url)
            return true
        }
        
        let finalResults = Array(uniqueResults.prefix(maxResults))
        
        guard !finalResults.isEmpty else {
            print("❌ WebSearch: No results from any source")
            throw SearchError.noResults
        }
        
        print("✅ WebSearch: Returning \(finalResults.count) results (DDG: \(ddgResults.count), Reddit: \(redditResults.count), Wiki: \(wikiResults.count))")
        lastSearchResults = finalResults
        return finalResults
    }
    
    // MARK: - DuckDuckGo Search
    private func searchDuckDuckGo(query: String, maxResults: Int) async -> [WebSearchResult] {
        do {
            return try await DuckDuckGoProvider().search(query: query, maxResults: maxResults)
        } catch {
            print("⚠️ DuckDuckGo search failed: \(error)")
            return []
        }
    }
    
    // MARK: - Reddit Search
    private func searchReddit(query: String, maxResults: Int) async -> [WebSearchResult] {
        do {
            return try await RedditProvider().search(query: query, maxResults: maxResults)
        } catch {
            print("⚠️ Reddit search failed: \(error)")
            return []
        }
    }
    
    // MARK: - Wikipedia Search
    private func searchWikipedia(query: String, maxResults: Int) async -> [WebSearchResult] {
        do {
            return try await WikipediaProvider().search(query: query, maxResults: maxResults)
        } catch {
            print("⚠️ Wikipedia search failed: \(error)")
            return []
        }
    }
}

// MARK: - DuckDuckGo Provider
private struct DuckDuckGoProvider: WebSearching {
    struct IAResponse: Decodable {
        struct Topic: Decodable { 
            let FirstURL: String
            let Text: String 
        }
        let AbstractURL: String?
        let AbstractText: String?
        let RelatedTopics: [Topic]?
        let Heading: String?
    }

    func search(query: String, maxResults: Int) async throws -> [WebSearchResult] {
        var components = URLComponents(string: "https://api.duckduckgo.com/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "t", value: "PaceAndPlates"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1")
        ]
        
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WebSearchService.SearchError.noResults
        }

        let decoded = try JSONDecoder().decode(IAResponse.self, from: data)
        var results: [WebSearchResult] = []

        if let absText = decoded.AbstractText, let absURL = decoded.AbstractURL,
           !absText.isEmpty, !absURL.isEmpty {
            results.append(WebSearchResult(
                title: decoded.Heading ?? "DuckDuckGo Result",
                url: absURL,
                snippet: absText,
                source: "DuckDuckGo"
            ))
        }

        if let related = decoded.RelatedTopics {
            for topic in related.prefix(maxResults - results.count) where !topic.Text.isEmpty && !topic.FirstURL.isEmpty {
                results.append(WebSearchResult(
                    title: String(topic.Text.prefix(100)),
                    url: topic.FirstURL,
                    snippet: topic.Text,
                    source: "DuckDuckGo"
                ))
            }
        }

        return results
    }
}

// MARK: - Reddit Provider
private struct RedditProvider: WebSearching {
    struct RedditResponse: Decodable {
        struct Data: Decodable {
            struct Child: Decodable {
                struct PostData: Decodable {
                    let title: String
                    let selftext: String?
                    let permalink: String
                    let subreddit: String
                    let score: Int?
                }
                let data: PostData
            }
            let children: [Child]
        }
        let data: Data
    }
    
    func search(query: String, maxResults: Int) async throws -> [WebSearchResult] {
        // Search fitness-related subreddits for relevant community insights
        let subreddits = ["fitness", "weightlifting", "nutrition", "running", "bodybuilding"]
        let subredditQuery = subreddits.joined(separator: "+")
        
        var components = URLComponents(string: "https://www.reddit.com/r/\(subredditQuery)/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(min(maxResults, 5))),
            URLQueryItem(name: "sort", value: "relevance"),
            URLQueryItem(name: "restrict_sr", value: "on")
        ]
        
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8.0
        request.setValue("PaceAndPlates/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }
        
        let decoded = try JSONDecoder().decode(RedditResponse.self, from: data)
        var results: [WebSearchResult] = []
        
        for child in decoded.data.children.prefix(maxResults) {
            let post = child.data
            let snippet = post.selftext?.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines) ?? post.title
            
            results.append(WebSearchResult(
                title: "r/\(post.subreddit): \(post.title)",
                url: "https://reddit.com\(post.permalink)",
                snippet: String(snippet),
                source: "Reddit"
            ))
        }
        
        return results
    }
}

// MARK: - Wikipedia Provider
private struct WikipediaProvider: WebSearching {
    struct WikiResponse: Decodable {
        struct Query: Decodable {
            struct Page: Decodable {
                let pageid: Int
                let title: String
                let extract: String?
            }
            let pages: [String: Page]
        }
        let query: Query?
    }
    
    func search(query: String, maxResults: Int) async throws -> [WebSearchResult] {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: query),
            URLQueryItem(name: "gsrlimit", value: String(min(maxResults, 3))),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exsentences", value: "2")
        ]
        
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }
        
        let decoded = try JSONDecoder().decode(WikiResponse.self, from: data)
        var results: [WebSearchResult] = []
        
        if let pages = decoded.query?.pages {
            for (_, page) in pages.prefix(maxResults) {
                let snippet = page.extract?.prefix(250).trimmingCharacters(in: .whitespacesAndNewlines) ?? page.title
                
                results.append(WebSearchResult(
                    title: page.title,
                    url: "https://en.wikipedia.org/?curid=\(page.pageid)",
                    snippet: String(snippet),
                    source: "Wikipedia"
                ))
            }
        }
        
        return results
    }
}

// MARK: - Prompt Context Helper
extension WebSearchService {
    static func formattedContext(for results: [WebSearchResult], maxChars: Int = 1200, includeCitations: Bool = false) -> String {
        var lines: [String] = []

        if includeCitations {
            lines.append("=== VERIFIED SOURCES (DuckDuckGo, Reddit, Wikipedia) ===")
            lines.append("Cite sources as [1], [2], etc. in your response.")
            lines.append("")
        } else {
            lines.append("=== WEB CONTEXT ===")
        }

        for (index, result) in results.enumerated() {
            let snippet = result.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            let condensedSnippet = String(snippet.prefix(200))

            if includeCitations {
                lines.append("[\(index + 1)] \(result.title)")
                lines.append("    \(condensedSnippet)")
                lines.append("    (\(result.source))")
                lines.append("")
            } else {
                lines.append("- [\(index + 1)] \(result.title) (\(result.source))")
                lines.append("  \(condensedSnippet)")
            }

            if lines.joined().count > maxChars { break }
        }

        if includeCitations {
            lines.append("=== END VERIFIED SOURCES ===")
        } else {
            lines.append("=== END WEB CONTEXT ===")
        }

        return lines.joined(separator: "\n")
    }
}


