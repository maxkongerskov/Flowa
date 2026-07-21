// LanguageOption.swift
// Flowa
//
// Whisper large-v3 / large-v3-turbo language catalog (99 codes + Auto-detect).

import Foundation

struct LanguageOption: Equatable {
    let code: String
    let displayName: String

    static let all: [LanguageOption] = {
        let auto = LanguageOption(code: "auto", displayName: "Auto-detect")
        let langs: [LanguageOption] = [
            LanguageOption(code: "af",  displayName: "Afrikaans"),
            LanguageOption(code: "sq",  displayName: "Albanian"),
            LanguageOption(code: "am",  displayName: "Amharic"),
            LanguageOption(code: "ar",  displayName: "Arabic"),
            LanguageOption(code: "hy",  displayName: "Armenian"),
            LanguageOption(code: "as",  displayName: "Assamese"),
            LanguageOption(code: "az",  displayName: "Azerbaijani"),
            LanguageOption(code: "ba",  displayName: "Bashkir"),
            LanguageOption(code: "eu",  displayName: "Basque"),
            LanguageOption(code: "be",  displayName: "Belarusian"),
            LanguageOption(code: "bn",  displayName: "Bengali"),
            LanguageOption(code: "bs",  displayName: "Bosnian"),
            LanguageOption(code: "br",  displayName: "Breton"),
            LanguageOption(code: "bg",  displayName: "Bulgarian"),
            LanguageOption(code: "my",  displayName: "Burmese"),
            LanguageOption(code: "yue", displayName: "Cantonese"),
            LanguageOption(code: "ca",  displayName: "Catalan"),
            LanguageOption(code: "zh",  displayName: "Chinese"),
            LanguageOption(code: "hr",  displayName: "Croatian"),
            LanguageOption(code: "cs",  displayName: "Czech"),
            LanguageOption(code: "da",  displayName: "Danish"),
            LanguageOption(code: "nl",  displayName: "Dutch"),
            LanguageOption(code: "en",  displayName: "English"),
            LanguageOption(code: "et",  displayName: "Estonian"),
            LanguageOption(code: "fo",  displayName: "Faroese"),
            LanguageOption(code: "fi",  displayName: "Finnish"),
            LanguageOption(code: "fr",  displayName: "French"),
            LanguageOption(code: "gl",  displayName: "Galician"),
            LanguageOption(code: "ka",  displayName: "Georgian"),
            LanguageOption(code: "de",  displayName: "German"),
            LanguageOption(code: "el",  displayName: "Greek"),
            LanguageOption(code: "gu",  displayName: "Gujarati"),
            LanguageOption(code: "ht",  displayName: "Haitian Creole"),
            LanguageOption(code: "ha",  displayName: "Hausa"),
            LanguageOption(code: "haw", displayName: "Hawaiian"),
            LanguageOption(code: "he",  displayName: "Hebrew"),
            LanguageOption(code: "hi",  displayName: "Hindi"),
            LanguageOption(code: "hu",  displayName: "Hungarian"),
            LanguageOption(code: "is",  displayName: "Icelandic"),
            LanguageOption(code: "id",  displayName: "Indonesian"),
            LanguageOption(code: "it",  displayName: "Italian"),
            LanguageOption(code: "ja",  displayName: "Japanese"),
            LanguageOption(code: "jw",  displayName: "Javanese"),
            LanguageOption(code: "kn",  displayName: "Kannada"),
            LanguageOption(code: "kk",  displayName: "Kazakh"),
            LanguageOption(code: "km",  displayName: "Khmer"),
            LanguageOption(code: "ko",  displayName: "Korean"),
            LanguageOption(code: "lo",  displayName: "Lao"),
            LanguageOption(code: "la",  displayName: "Latin"),
            LanguageOption(code: "lv",  displayName: "Latvian"),
            LanguageOption(code: "ln",  displayName: "Lingala"),
            LanguageOption(code: "lt",  displayName: "Lithuanian"),
            LanguageOption(code: "lb",  displayName: "Luxembourgish"),
            LanguageOption(code: "mk",  displayName: "Macedonian"),
            LanguageOption(code: "mg",  displayName: "Malagasy"),
            LanguageOption(code: "ms",  displayName: "Malay"),
            LanguageOption(code: "ml",  displayName: "Malayalam"),
            LanguageOption(code: "mt",  displayName: "Maltese"),
            LanguageOption(code: "mi",  displayName: "Maori"),
            LanguageOption(code: "mr",  displayName: "Marathi"),
            LanguageOption(code: "mn",  displayName: "Mongolian"),
            LanguageOption(code: "ne",  displayName: "Nepali"),
            LanguageOption(code: "no",  displayName: "Norwegian"),
            LanguageOption(code: "nn",  displayName: "Norwegian Nynorsk"),
            LanguageOption(code: "oc",  displayName: "Occitan"),
            LanguageOption(code: "ps",  displayName: "Pashto"),
            LanguageOption(code: "fa",  displayName: "Persian"),
            LanguageOption(code: "pl",  displayName: "Polish"),
            LanguageOption(code: "pt",  displayName: "Portuguese"),
            LanguageOption(code: "pa",  displayName: "Punjabi"),
            LanguageOption(code: "ro",  displayName: "Romanian"),
            LanguageOption(code: "ru",  displayName: "Russian"),
            LanguageOption(code: "sa",  displayName: "Sanskrit"),
            LanguageOption(code: "sr",  displayName: "Serbian"),
            LanguageOption(code: "sn",  displayName: "Shona"),
            LanguageOption(code: "sd",  displayName: "Sindhi"),
            LanguageOption(code: "si",  displayName: "Sinhala"),
            LanguageOption(code: "sk",  displayName: "Slovak"),
            LanguageOption(code: "sl",  displayName: "Slovenian"),
            LanguageOption(code: "so",  displayName: "Somali"),
            LanguageOption(code: "es",  displayName: "Spanish"),
            LanguageOption(code: "su",  displayName: "Sundanese"),
            LanguageOption(code: "sw",  displayName: "Swahili"),
            LanguageOption(code: "sv",  displayName: "Swedish"),
            LanguageOption(code: "tl",  displayName: "Tagalog"),
            LanguageOption(code: "tg",  displayName: "Tajik"),
            LanguageOption(code: "ta",  displayName: "Tamil"),
            LanguageOption(code: "tt",  displayName: "Tatar"),
            LanguageOption(code: "te",  displayName: "Telugu"),
            LanguageOption(code: "th",  displayName: "Thai"),
            LanguageOption(code: "bo",  displayName: "Tibetan"),
            LanguageOption(code: "tr",  displayName: "Turkish"),
            LanguageOption(code: "tk",  displayName: "Turkmen"),
            LanguageOption(code: "uk",  displayName: "Ukrainian"),
            LanguageOption(code: "ur",  displayName: "Urdu"),
            LanguageOption(code: "uz",  displayName: "Uzbek"),
            LanguageOption(code: "vi",  displayName: "Vietnamese"),
            LanguageOption(code: "cy",  displayName: "Welsh"),
            LanguageOption(code: "yi",  displayName: "Yiddish"),
            LanguageOption(code: "yo",  displayName: "Yoruba"),
        ]
        return [auto] + langs.sorted { $0.displayName < $1.displayName }
    }()

    static func displayName(for code: String) -> String {
        all.first(where: { $0.code == code })?.displayName ?? code
    }

    static func filtered(query: String) -> [LanguageOption] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.displayName.lowercased().contains(q)
                || $0.code.lowercased().hasPrefix(q)
        }
    }
}
