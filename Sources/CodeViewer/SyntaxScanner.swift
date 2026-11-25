import AppKit

/// How one language is scanned. Languages that share a shape (comment
/// syntax, string quoting, keyword style) share a dialect, so the generic
/// pass in `SyntaxScanner` needs only these settings to tell tokens apart.
struct Dialect: Sendable {
    var lineComments: [String] = ["//"]
    var blockComments: [(open: String, close: String)] = [("/*", "*/")]
    var nestedBlockComments = false
    /// Quoted strings with backslash escapes.
    var quotes: [Unicode.Scalar] = ["\"", "'"]
    /// Triple-quoted strings (Python docstrings, Swift multi-line literals).
    var tripleQuotes: [String] = []
    /// Raw strings without escapes: Go backticks, Lua long brackets.
    var verbatimStrings: [(open: String, close: String)] = []
    /// Swift raw strings `#"…"#`.
    var hashRawStrings = false
    var keywords: Set<String>
    var caseInsensitiveKeywords = false
    /// Stored lowercased; identifiers are compared lowercased.
    var literals: Set<String> = ["true", "false", "null", "nil"]
    var builtIns: Set<String> = []
    var capitalizedNamesAreTypes = true
    /// Erlang: a capitalized name is a variable instead.
    var capitalizedNamesAreVariables = false
    /// `@Annotation` → meta.
    var annotationPrefix: Unicode.Scalar? = nil
    enum Preprocessor: Sendable { case lineStart, anywhere }
    /// `#directive` → meta, at the start of a line (C) or anywhere (Swift).
    var preprocessor: Preprocessor? = nil
    /// Rust `#[derive(…)]` / `#![…]` → meta.
    var bracketAttributes = false
    /// `$var`, `@ivar` → variable.
    var variablePrefixes: [Unicode.Scalar] = []
    /// Ruby / Elixir / Clojure `:symbol` → symbol.
    var symbolPrefix: Unicode.Scalar? = nil
    /// Erlang `?MACRO` → meta.
    var macroPrefix: Unicode.Scalar? = nil
}

private extension Dialect {
    func with(annotationPrefix: Unicode.Scalar?) -> Dialect {
        var copy = self
        copy.annotationPrefix = annotationPrefix
        return copy
    }
}

/// Which scanner pass a language gets.
enum ScanMode: Sendable {
    case code(Dialect)
    case markup
    case stylesheet
    case markdown
    case json
    case yaml
    case ini
    case diff
}

/// The language table: canonical language name (see `SyntaxLanguageMapper`)
/// → scan mode. Every name the mapper can produce must have an entry; a
/// missing one renders plain text.
enum LanguageRules {
    static func mode(for language: String) -> ScanMode? { modes[language] }

    static var languages: [String] { Array(modes.keys) }

    private static func words(_ list: String) -> Set<String> {
        Set(list.split(separator: " ").map(String.init))
    }

    private static let cKeywords = words("""
    as auto break case catch class const continue default delete do else enum export extern for friend \
    goto if import inline namespace new operator private protected public register return sizeof static \
    struct switch template this throw try typedef typename union using virtual void volatile while \
    bool char double float int long short signed unsigned size_t ssize_t int8_t int16_t int32_t int64_t \
    uint8_t uint16_t uint32_t uint64_t
    """)

    private static let swiftKeywords = words("""
    actor any as associatedtype async await break case catch class continue default defer do else enum \
    extension fallthrough fileprivate for func guard if import in init inout internal is let \
    open operator private protocol public repeat rethrows return self Self some static struct subscript \
    super switch throw throws try typealias var where while get set required convenience override \
    lazy weak unowned owned borrowing consuming mutating nonmutating package
    """)

    private static let javaKeywords = words("""
    abstract assert boolean break byte case catch char class const continue default do double else enum \
    extends final finally float for goto if implements import instanceof int interface long native new \
    package private protected public record return sealed permits short static strictfp super switch \
    synchronized this throw throws transient try var void volatile while yield
    """)

    private static let kotlinKeywords = words("""
    as break by class companion const continue crossinline data do else enum external field file \
    finally for fun get if import in infix init inline interface internal is lateinit noinline object \
    open operator out override package private property protected public return set super suspend tailrec \
    this throw try typealias val value var vararg when where while
    """)

    private static let scalaKeywords = words("""
    abstract case catch class def derives enum export extension final finally for given if implicit \
    import infix lazy match new object override package private protected return sealed super then throw \
    trait try type val var while with yield
    """)

    private static let dartKeywords = words("""
    abstract as assert async await base break case catch class const continue covariant default deferred \
    do dynamic else enum export extends extension external factory final finally for Function get \
    hide if implements import in interface is late library mixin new on operator part required \
    return sealed set show static super switch sync this throw try typedef var void when while with \
    yield
    """)

    private static let csharpKeywords = words("""
    abstract as async await base bool break byte case catch char checked class const continue decimal \
    default delegate do double else enum event explicit extern finally fixed float for foreach goto \
    if implicit in int interface internal is lock long namespace new object operator out override \
    params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string \
    struct switch this throw try typeof uint ulong unchecked unsafe ushort using virtual void \
    volatile while record
    """)

    private static let jsKeywords = words("""
    abstract any as async await break case catch class const continue debugger declare default delete do \
    else enum export extends finally for from function get if implements import in infer instanceof \
    interface keyof let namespace never of readonly return satisfy set static super switch symbol this \
    throw try type typeof var void while with yield
    """)

    private static let goKeywords = words("""
    break case chan const continue default defer else fallthrough for func go goto if import interface map \
    package range return select struct switch type var
    """)

    private static let rustKeywords = words("""
    as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod \
    move mut pub ref return self Self static struct super trait type union unsafe use where while
    """)

    private static let phpKeywords = words("""
    abstract and array as break callable case catch class clone const continue declare default do echo \
    else elseif empty enddeclare endfor endforeach endif endswitch endwhile enum extends final finally fn \
    for foreach from function global goto if implements include include_once instanceof insteadof \
    interface isset list match namespace new or print private protected public readonly require \
    require_once return static switch throw trait try unset use var while xor yield
    """)

    private static let pythonKeywords = words("""
    and as assert async await break class continue def del elif else except finally for from global if \
    import in is lambda nonlocal not or pass raise return try type while with yield match case
    """)

    private static let rubyKeywords = words("""
    alias begin break case class def defined? do else elsif end ensure for if in module next not or redo \
    rescue retry return self super then undef unless until when while yield require require_relative \
    include extend attr_accessor attr_reader attr_writer raise loop lambda proc new puts print p
    """)

    private static let shellKeywords = words("""
    if then else elif fi for while until do done case esac in function select time return exit local \
    export readonly declare typeset unset eval trap let shift set pushd popd
    """)

    private static let powershellKeywords = words("""
    begin process end function param return if elseif else switch foreach for while do until break \
    continue try catch finally throw trap class enum using in parallel sequence workflow
    """)

    private static let perlKeywords = words("""
    if elsif else unless while until for foreach do continue given when default break return sub package \
    use require no my our local state and or not xor cmp eq ne lt gt le ge print say die warn push pop shift \
    unshift keys values each map grep sort reverse chomp split join sprintf open close bless
    """)

    private static let luaKeywords = words("""
    and break do else elseif end for function goto if in local not or repeat return then until while
    """)

    private static let sqlKeywords = words("""
    select from where insert into values update set delete create table drop alter add column primary key \
    foreign references join left right inner outer full cross on as group by order having limit offset \
    union all distinct and or not is in between like exists case when then end index view trigger \
    begin commit rollback transaction with recursive default unique check constraint asc desc returning \
    using natural over partition fetch next rows only concat substring length upper lower trim replace \
    now current_timestamp current_date extract interval cast convert coalesce ifnull top
    """)

    private static let dockerKeywords = words("""
    from run cmd label expose env add copy entrypoint volume user workdir arg onbuild stopsignal \
    healthcheck shell maintain
    """)

    private static let makeKeywords = words("""
    define endef ifdef ifndef ifeq ifneq else endif include override export unexport undefine vpath
    """)

    private static let elixirKeywords = words("""
    alias case cond def defp defmodule defprotocol defimpl defmacro defmacrop do else end fn for if \
    import not or and rescue raise require reraise receive try catch throw unquote when while with after
    """)

    private static let erlangKeywords = words("""
    after and andalso band begin bnot bor bsl bsr bxor case catch cond div end fun if let not of or \
    orelse receive rem try when xor
    """)

    private static let clojureKeywords = words("""
    def defn defn- fn let letfn loop do if when if-not when-not cond case condp doto and or not ns \
    require import use refer declare defmulti defmethod defrecord defprotocol definterface
    """)

    private static let juliaKeywords = words("""
    begin while if for try return function macro quote let local global const do struct abstract type \
    mutable break continue module baremodule using import export public as catch finally where
    """)

    private static let haskellKeywords = words("""
    case of data newtype type class instance deriving where let in do module import qualified hiding \
    infix infixl infixr if then else
    """)

    private static let fortranKeywords = words("""
    program end module use implicit none subroutine function result integer real character logical \
    complex double precision intent in out inout parameter allocatable pointer target dimension if then \
    elseif endif do while enddo select case default endselect endtype contains interface endinterface call \
    return stop cycle exit private public procedure pass bind
    """)

    private static let vbKeywords = words("""
    addhandler addressof alias and andalso as boolean byref byte byval call case catch class const \
    continue date decimal declare default delegate dim directcast do double each else elseif end enum \
    erase error event exit finally for friend function get gettype global gosub goto handles if \
    implements imports in inherits integer interface is isnot let lib like long loop me mod module \
    mustinherit mustoverride mybase myclass namespace narrowing new next not notinheritable \
    notoverridable object of on operator option optional or orelse overloads overridable overrides \
    paramarray partial private property protected public raiseevent readonly redim removehandler resume \
    return select set shadows shared short single static step stop structure sub synclock throw to \
    try trycast typeof uinteger ulong until ushort using variant wend when while widening with \
    withevents writeonly xor
    """)

    private static let vimKeywords = words("""
    augroup autocmd au command nmap vmap imap cmap nnoremap vnoremap inoremap xnoremap cnoremap map \
    let set setlocal setglobal function endfunction if elseif else endif for endfor while endwhile try \
    catch finally endtry call echo echom execute highlight hi syntax syn match start end colorscheme \
    source runtime filetype on off auto indent expandtab
    """)

    private static let graphqlKeywords = words("""
    query mutation subscription fragment on type input interface union scalar enum directive schema \
    extend repeatable
    """)

    private static let protobufKeywords = words("""
    syntax package import option message enum service rpc returns repeated optional required oneof map \
    reserved to max public
    """)

    private static let zigKeywords = words("""
    addrspace align allowzero and anyframe anytype asm async await break callconv catch comptime const \
    continue defer else enum errdefer error export extern fn for if inline linksection noalias noinline \
    nosuspend opaque or orelse packed pub resume return struct suspend switch test threadlocal try union \
    unreachable usingnamespace var volatile while
    """)

    private static let dosKeywords = words("""
    rem echo set if else exist for in do call goto pause exit cd dir copy del ren mkdir rmdir
    """)

    private static let cFamily = Dialect(
        keywords: cKeywords, literals: words("true false null nullptr nil"), preprocessor: .lineStart
    )

    private static let shell = Dialect(
        lineComments: ["#"], blockComments: [], keywords: shellKeywords,
        literals: ["true", "false"],
        builtIns: words("""
        cd echo printf read export local source alias eval test exit return pwd ls cp mv rm mkdir touch \
        chmod grep sed awk find sort uniq head tail cat curl wget git make swift type kill bg fg jobs wait
        """),
        variablePrefixes: ["$"]
    )

    private static let modes: [String: ScanMode] = {
        var modes: [String: ScanMode] = [:]
        func code(_ names: String, _ dialect: Dialect) {
            for name in names.split(separator: " ") { modes[String(name)] = .code(dialect) }
        }
        func same(_ names: String, _ mode: ScanMode) {
            for name in names.split(separator: " ") { modes[String(name)] = mode }
        }

        code("c cpp protobuf", cFamily)
        code("objectivec", cFamily.with(annotationPrefix: "@"))
        code("swift", Dialect(
            nestedBlockComments: true, quotes: ["\""], tripleQuotes: ["\"\"\""], hashRawStrings: true,
            keywords: swiftKeywords,
            builtIns: words("""
            print String Int Float Double Bool Character Array Dictionary Set Optional Result Void Never \
            Data Date URL Codable Equatable Hashable Identifiable Comparable Sendable NSObject NSColor \
            NSFont NSView NSImage NSTextView
            """),
            annotationPrefix: "@", preprocessor: .anywhere, variablePrefixes: ["$"]
        ))
        code("java", Dialect(
            keywords: javaKeywords,
            builtIns: words("""
            String System Math Object List Map Set Integer Long Double Boolean Float Character ArrayList \
            HashMap HashSet Iterator Optional Stream var void
            """),
            annotationPrefix: "@"
        ))
        code("csharp", Dialect(
            keywords: csharpKeywords,
            builtIns: words("""
            string int long double bool float char decimal object var dynamic List Dictionary HashSet \
            IEnumerable Task Console Math DateTime String
            """)
        ))
        code("javascript typescript", Dialect(
            quotes: ["\"", "'"], verbatimStrings: [("`", "`")], keywords: jsKeywords,
            literals: words("true false null undefined nan infinity"),
            builtIns: words("""
            console Math JSON Object Array Promise Date RegExp Map Set Symbol Reflect Proxy Intl \
            parseInt parseFloat isNaN setTimeout setInterval fetch require module exports process Buffer \
            document window Partial Readonly Record Pick Omit ReturnType Parameters
            """),
            annotationPrefix: "@"
        ))
        code("go", Dialect(
            quotes: ["\"", "'"], verbatimStrings: [("`", "`")], keywords: goKeywords,
            literals: words("true false nil iota"),
            builtIns: words("append cap close complex copy delete imag len make new panic print println real recover")
        ))
        code("rust", Dialect(
            nestedBlockComments: true, keywords: rustKeywords,
            literals: words("true false none some ok err"),
            builtIns: words("String Vec Option Result Box Rc Arc HashMap HashSet println print format vec"),
            bracketAttributes: true
        ))
        code("kotlin", Dialect(
            quotes: ["\""], tripleQuotes: ["\"\"\""], keywords: kotlinKeywords,
            builtIns: words("""
            String Int Long Double Boolean Float Char List Map Set Array Any Unit Nothing Object println
            """),
            annotationPrefix: "@"
        ))
        code("scala", Dialect(keywords: scalaKeywords, annotationPrefix: "@"))
        code("dart", Dialect(
            quotes: ["\"", "'"], tripleQuotes: ["\"\"\"", "'''"], keywords: dartKeywords,
            builtIns: words("""
            print String int double bool num List Map Set Future Stream Widget State StatelessWidget \
            StatefulWidget
            """),
            annotationPrefix: "@"
        ))
        code("php", Dialect(lineComments: ["//", "#"], keywords: phpKeywords, variablePrefixes: ["$"]))
        code("python", Dialect(
            lineComments: ["#"], blockComments: [], quotes: ["\"", "'"], tripleQuotes: ["\"\"\"", "'''"],
            keywords: pythonKeywords, literals: words("true false none notimplemented"),
            builtIns: words("""
            print len range str int float bool list dict set tuple type object super isinstance issubclass \
            enumerate zip map filter sorted reversed sum min max abs any all open input id hash repr format \
            hasattr getattr setattr callable iter next divmod pow round chr ord hex oct bin bytes bytearray \
            frozenset complex vars dir globals locals classmethod staticmethod property self cls
            """),
            annotationPrefix: "@"
        ))
        code("ruby", Dialect(
            lineComments: ["#"], blockComments: [], keywords: rubyKeywords,
            builtIns: words("""
            puts print p require require_relative attr_accessor attr_reader attr_writer include extend \
            raise new loop lambda proc
            """),
            variablePrefixes: ["@"], symbolPrefix: ":"
        ))
        code("bash fish", shell)
        code("powershell", Dialect(
            lineComments: ["#"], blockComments: [], keywords: powershellKeywords,
            caseInsensitiveKeywords: true, literals: [],
            builtIns: words("""
            Write-Host Write-Output Get-Item Get-ChildItem Set-Location Select-Object Where-Object \
            ForEach-Object New-Item Remove-Item Copy-Item Move-Item Test-Path
            """),
            variablePrefixes: ["$"]
        ))
        code("perl", Dialect(
            lineComments: ["#"], blockComments: [], keywords: perlKeywords, variablePrefixes: ["$", "@"]
        ))
        code("lua", Dialect(
            lineComments: ["--"], blockComments: [("--[[", "]]")], verbatimStrings: [("[[", "]]")],
            keywords: luaKeywords,
            builtIns: words("print pairs ipairs require tostring tonumber type string table math os io coroutine"),
            capitalizedNamesAreTypes: false
        ))
        code("sql", Dialect(
            lineComments: ["--"], quotes: ["'"], keywords: sqlKeywords, caseInsensitiveKeywords: true,
            literals: words("null true false"),
            capitalizedNamesAreTypes: false
        ))
        code("elixir", Dialect(
            lineComments: ["#"], blockComments: [], quotes: ["\"", "'"], tripleQuotes: ["\"\"\""],
            keywords: elixirKeywords,
            builtIns: words("IO Kernel Enum Map String List"),
            annotationPrefix: "@", symbolPrefix: ":"
        ))
        code("erlang", Dialect(
            lineComments: ["%"], blockComments: [], quotes: ["'"], keywords: erlangKeywords,
            literals: [],
            capitalizedNamesAreTypes: false, capitalizedNamesAreVariables: true, macroPrefix: "?"
        ))
        code("clojure", Dialect(
            lineComments: [";"], blockComments: [], quotes: ["\""], keywords: clojureKeywords,
            capitalizedNamesAreTypes: false, symbolPrefix: ":"
        ))
        code("julia", Dialect(
            lineComments: ["#"], blockComments: [], quotes: ["\"", "'"], tripleQuotes: ["\"\"\""],
            keywords: juliaKeywords, literals: words("true false nothing"),
            builtIns: words("println print rand sqrt exp log abs length push! append! zeros ones")
        ))
        code("haskell", Dialect(
            lineComments: ["--"], blockComments: [("{-", "-}")], keywords: haskellKeywords,
            literals: words("true false")
        ))
        code("fortran", Dialect(
            lineComments: ["!"], blockComments: [], keywords: fortranKeywords,
            caseInsensitiveKeywords: true, literals: words("true false"),
            capitalizedNamesAreTypes: false
        ))
        code("vbnet", Dialect(
            lineComments: ["'"], blockComments: [], quotes: ["\""], keywords: vbKeywords,
            caseInsensitiveKeywords: true, literals: words("true false nothing"),
            capitalizedNamesAreTypes: false
        ))
        code("vim", Dialect(
            lineComments: ["\""], blockComments: [], quotes: ["\""], keywords: vimKeywords,
            capitalizedNamesAreTypes: false
        ))
        code("dockerfile", Dialect(
            lineComments: ["#"], blockComments: [], quotes: ["\"", "'"], keywords: dockerKeywords,
            caseInsensitiveKeywords: true, literals: [], capitalizedNamesAreTypes: false
        ))
        code("makefile", Dialect(
            lineComments: ["#"], blockComments: [], quotes: ["\"", "'"], keywords: makeKeywords,
            literals: [], capitalizedNamesAreTypes: false, variablePrefixes: ["$"]
        ))
        code("graphql", Dialect(
            lineComments: ["#"], blockComments: [], quotes: ["\""], tripleQuotes: ["\"\"\""],
            keywords: graphqlKeywords, literals: words("true false null")
        ))
        code("dos", Dialect(
            lineComments: ["::"], blockComments: [], quotes: ["\""], keywords: dosKeywords,
            caseInsensitiveKeywords: true, literals: [], capitalizedNamesAreTypes: false
        ))
        code("zig", Dialect(
            keywords: zigKeywords, literals: words("true false null undefined"), annotationPrefix: "@"
        ))

        same("markdown", .markdown)
        same("xml", .markup)
        same("css scss less", .stylesheet)
        same("json", .json)
        same("yaml", .yaml)
        same("ini", .ini)
        same("diff", .diff)
        return modes
    }()
}

/// Single-pass lexical scanner. Walks the text as Unicode scalars, classifies
/// each run into a `TokenKind` and appends it to an attributed string with the
/// theme's color for that kind. Characters are never changed, so the output
/// is always a 1:1 restyle of the input. Pure and stateless apart from its
/// own output, so it runs safely on a background task.
final class SyntaxScanner {
    /// Trait markers only: `CodeTextFactory.styled` resolves them against the
    /// editor font, so the size here never reaches the screen.
    static let boldMarker = NSFont.systemFont(ofSize: 13, weight: .bold)
    static let italicMarker: NSFont = {
        let descriptor = NSFont.systemFont(ofSize: 13).fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: 13) ?? NSFont.systemFont(ofSize: 13)
    }()

    static func attributedString(for text: String, language: String, theme: EditorTheme) -> NSAttributedString {
        guard let mode = LanguageRules.mode(for: language) else {
            let result = NSMutableAttributedString(string: text)
            if !text.isEmpty {
                result.addAttribute(
                    .foregroundColor,
                    value: theme.color(for: .plain),
                    range: NSRange(location: 0, length: result.length)
                )
            }
            return result
        }
        let scanner = SyntaxScanner(text: text, theme: theme)
        scanner.run(mode)
        return scanner.output
    }

    private let scalars: [Unicode.Scalar]
    private let palette: EditorTheme
    private let output = NSMutableAttributedString()
    private var index = 0

    private init(text: String, theme: EditorTheme) {
        self.scalars = Array(text.unicodeScalars)
        self.palette = theme
    }

    private var count: Int { scalars.count }
    private var current: Unicode.Scalar? { scalarAt(index) }

    private func scalarAt(_ position: Int) -> Unicode.Scalar? {
        position >= 0 && position < count ? scalars[position] : nil
    }

    private func peek(_ offset: Int = 1) -> Unicode.Scalar? { scalarAt(index + offset) }

    private func text(_ from: Int, _ to: Int) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[from..<to])
        return String(view)
    }

    private func matches(_ literal: String, at position: Int? = nil) -> Bool {
        let position = position ?? index
        var offset = 0
        for scalar in literal.unicodeScalars {
            guard scalarAt(position + offset) == scalar else { return false }
            offset += 1
        }
        return true
    }

    private func emit(_ kind: TokenKind, from start: Int, to end: Int? = nil, bold: Bool = false, italic: Bool = false) {
        let end = end ?? index
        guard end > start else { return }
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: palette.color(for: kind)]
        if bold { attributes[.font] = Self.boldMarker }
        if italic { attributes[.font] = Self.italicMarker }
        output.append(NSAttributedString(string: text(start, end), attributes: attributes))
    }

    private func run(_ mode: ScanMode) {
        switch mode {
        case .code(let dialect): scanCode(dialect)
        case .markup: scanMarkup()
        case .stylesheet: scanStylesheet()
        case .markdown: scanMarkdown()
        case .json: scanJSON()
        case .yaml: scanYAML()
        case .ini: scanINI()
        case .diff: scanDiff()
        }
        // Every pass above runs to the end; this only guards against a
        // future early exit leaving the tail unstyled.
        if index < count {
            emit(.plain, from: index, to: count)
            index = count
        }
    }

    // MARK: - Generic code

    private func scanCode(_ dialect: Dialect) {
        while let scalar = current {
            let start = index
            if scalar.isWhitespace {
                index = whitespaceEnd(from: start)
                emit(.plain, from: start)
            } else if consumeComment(dialect) {
                emit(.comment, from: start)
            } else if consumePreprocessorOrAnnotation(dialect) {
                // emitted by the consumer
            } else if consumeString(dialect) {
                emit(.string, from: start)
            } else if consumeVariable(dialect) {
                emit(.variable, from: start)
            } else if consumeSymbol(dialect) {
                emit(.symbol, from: start)
            } else if consumeMacro(dialect) {
                emit(.meta, from: start)
            } else if scalar.isASCIIDigit || (scalar == "." && peek()?.isASCIIDigit == true) {
                index = numberEnd(from: start)
                emit(.number, from: start)
            } else if scalar.isIdentifierStart {
                index = identifierEnd(from: start)
                emit(classify(text(start, index), dialect: dialect), from: start)
            } else if scalar.isPunctuation {
                while let next = current, next.isPunctuation { index += 1 }
                emit(.punctuation, from: start)
            } else if scalar.isOperator {
                while let next = current, next.isOperator { index += 1 }
                emit(.operatorSymbol, from: start)
            } else {
                index += 1
                emit(.plain, from: start)
            }
        }
    }

    private func whitespaceEnd(from start: Int) -> Int {
        var position = start
        while let scalar = scalarAt(position), scalar.isWhitespace { position += 1 }
        return position
    }

    private func identifierEnd(from start: Int) -> Int {
        var position = start
        while let scalar = scalarAt(position), scalar.isIdentifierContinue { position += 1 }
        return position
    }

    /// CSS names may contain `-` (`-webkit-`, `--custom`).
    private func cssIdentifierEnd(from start: Int) -> Int {
        var position = start
        while let scalar = scalarAt(position), scalar.isIdentifierContinue || scalar == "-" { position += 1 }
        return position
    }

    /// Integers (decimal, `0x`/`0o`/`0b`), floats with exponents and type
    /// suffixes, with `_` digit separators. Accepts a leading sign for the
    /// data formats that use one (JSON, YAML, INI).
    private func numberEnd(from start: Int) -> Int {
        var position = start
        if scalarAt(position) == "-" || scalarAt(position) == "+" { position += 1 }
        if scalarAt(position) == "." { position += 1 }
        while let scalar = scalarAt(position) {
            if scalar.isASCIIAlphanumeric || scalar == "_" {
                if scalar == "e" || scalar == "E",
                   let sign = scalarAt(position + 1), sign == "+" || sign == "-",
                   scalarAt(position + 2)?.isASCIIDigit == true {
                    position += 3
                    continue
                }
                position += 1
            } else if scalar == ".", scalarAt(position + 1)?.isASCIIDigit == true {
                position += 1
            } else {
                break
            }
        }
        return max(position, start + 1)
    }

    /// Line comments run to (not including) the newline; block comments may
    /// nest (Swift, Rust).
    private func consumeComment(_ dialect: Dialect) -> Bool {
        for prefix in dialect.lineComments where matches(prefix) {
            consumeLine()
            return true
        }
        for comment in dialect.blockComments where matches(comment.open) {
            index += comment.open.unicodeScalars.count
            if dialect.nestedBlockComments {
                var depth = 1
                while depth > 0, index < count {
                    if matches(comment.open) {
                        depth += 1
                        index += comment.open.unicodeScalars.count
                    } else if matches(comment.close) {
                        depth -= 1
                        index += comment.close.unicodeScalars.count
                    } else {
                        index += 1
                    }
                }
            } else {
                consumeUntil(comment.close, including: true)
            }
            return true
        }
        return false
    }

    /// `@Annotation`, `#[attribute]` and `#directive` all land in meta.
    private func consumePreprocessorOrAnnotation(_ dialect: Dialect) -> Bool {
        guard let scalar = current else { return false }
        let start = index
        if scalar == "#", dialect.bracketAttributes,
           peek() == "[" || (peek() == "!" && peek(2) == "[") {
            index += 1
            if current == "!" { index += 1 }
            var depth = 0
            while let inner = current {
                index += 1
                if inner == "[" {
                    depth += 1
                } else if inner == "]" {
                    depth -= 1
                    if depth == 0 { break }
                }
            }
            emit(.meta, from: start)
            return true
        }
        if let prefix = dialect.annotationPrefix, scalar == prefix, peek()?.isIdentifierStart == true {
            index = identifierEnd(from: index + 1)
            // `@objc(name)` keeps only the name; `@Foo.bar` keeps the path.
            while current == ".", let after = peek(), after.isIdentifierStart {
                index = identifierEnd(from: index + 1)
            }
            emit(.meta, from: start)
            return true
        }
        if scalar == "#", let style = dialect.preprocessor,
           style == .anywhere || isAtLineStart(), peek()?.isIdentifierStart == true {
            let nameStart = index + 1
            index = identifierEnd(from: nameStart)
            let directive = text(nameStart, index).lowercased()
            if directive == "include" || directive == "import" {
                var probe = index
                while let next = scalarAt(probe), next == " " || next == "\t" { probe += 1 }
                if scalarAt(probe) == "<" {
                    emit(.meta, from: start)
                    emit(.plain, from: index, to: probe)
                    index = probe
                    while let next = current, next != ">" && next != "\n" { index += 1 }
                    if current == ">" { index += 1 }
                    emit(.string, from: probe)
                    return true
                }
            }
            emit(.meta, from: start)
            return true
        }
        return false
    }

    /// Whether only whitespace precedes on the line.
    private func isAtLineStart() -> Bool {
        var position = index
        while let scalar = scalarAt(position - 1), scalar == " " || scalar == "\t" { position -= 1 }
        return position == 0 || scalarAt(position - 1) == "\n"
    }

    /// Quoted, triple-quoted, raw and verbatim strings.
    private func consumeString(_ dialect: Dialect) -> Bool {
        guard let scalar = current else { return false }
        for triple in dialect.tripleQuotes where matches(triple) {
            consumeUntil(triple, from: index + 3, including: true)
            return true
        }
        for raw in dialect.verbatimStrings where matches(raw.open) {
            consumeUntil(raw.close, from: index + raw.open.unicodeScalars.count, including: true)
            return true
        }
        if dialect.hashRawStrings, scalar == "#" {
            var hashes = 0
            while scalarAt(index + hashes) == "#" { hashes += 1 }
            let stringStart = index + hashes
            if matches("\"", at: stringStart) || matches("\"\"\"", at: stringStart) {
                let triple = matches("\"\"\"", at: stringStart)
                let closing = (triple ? "\"\"\"" : "\"") + String(repeating: "#", count: hashes)
                consumeUntil(closing, from: stringStart + (triple ? 3 : 1), including: true)
                return true
            }
        }
        guard dialect.quotes.contains(scalar) else { return false }
        consumeQuoted(scalar)
        return true
    }

    /// From the opening quote; a backslash escapes the next scalar. An
    /// unterminated string stops at the end of its line so one stray quote
    /// cannot swallow the rest of the file.
    private func consumeQuoted(_ quote: Unicode.Scalar) {
        index += 1
        while let scalar = current {
            if scalar == "\n" {
                break
            } else if scalar == "\\" {
                index = min(count, index + 2)
            } else if scalar == quote {
                index += 1
                break
            } else {
                index += 1
            }
        }
    }

    /// `$name`, `${name}`, `$(cmd)`, `$0`, `$@`, `@ivar`, `@@cvar`.
    private func consumeVariable(_ dialect: Dialect) -> Bool {
        guard let scalar = current, dialect.variablePrefixes.contains(scalar) else { return false }
        let start = index
        index += 1
        if scalar == "@", current == "@" { index += 1 }
        if let next = current {
            if next == "{" || next == "(" {
                let close: Unicode.Scalar = next == "{" ? "}" : ")"
                var depth = 0
                while let inner = current {
                    index += 1
                    if inner == next { depth += 1 }
                    if inner == close {
                        depth -= 1
                        if depth == 0 { break }
                    }
                }
                return true
            }
            if next.isIdentifierStart || next.isASCIIDigit {
                index = identifierEnd(from: index)
                return true
            }
            if scalar == "$", "@?#!$-*<^_|".unicodeScalars.contains(next) {
                index += 1
                return true
            }
        }
        index = start
        return false
    }

    /// Ruby / Elixir / Clojure `:symbol`.
    private func consumeSymbol(_ dialect: Dialect) -> Bool {
        guard let prefix = dialect.symbolPrefix, current == prefix,
              peek()?.isIdentifierStart == true else { return false }
        index = identifierEnd(from: index + 1)
        return true
    }

    /// Erlang `?MODULE`.
    private func consumeMacro(_ dialect: Dialect) -> Bool {
        guard let prefix = dialect.macroPrefix, current == prefix,
              peek()?.isIdentifierStart == true else { return false }
        index = identifierEnd(from: index + 1)
        return true
    }

    private func classify(_ name: String, dialect: Dialect) -> TokenKind {
        let lookup = dialect.caseInsensitiveKeywords ? name.lowercased() : name
        if dialect.keywords.contains(lookup) { return .keyword }
        if dialect.literals.contains(name.lowercased()) { return .literal }
        if dialect.builtIns.contains(name) { return .builtIn }
        let capitalized = name.unicodeScalars.first?.properties.isUppercase == true
        if capitalized, dialect.capitalizedNamesAreTypes { return .type }
        if isFollowedByCall() { return .function }
        if capitalized, dialect.capitalizedNamesAreVariables { return .variable }
        return .plain
    }

    /// Whether the next non-space scalar opens a call: `foo (`.
    private func isFollowedByCall() -> Bool {
        var probe = index
        while let scalar = scalarAt(probe), scalar == " " || scalar == "\t" { probe += 1 }
        return scalarAt(probe) == "("
    }

    private func consumeLine() {
        while let scalar = current, scalar != "\n" { index += 1 }
    }

    /// Moves `index` past `marker` if it appears from `from` on, else to the end.
    private func consumeUntil(_ marker: String, from: Int? = nil, including: Bool) {
        let from = from ?? index
        var probe = from
        let length = marker.unicodeScalars.count
        while probe + length <= count {
            if matches(marker, at: probe) {
                index = including ? probe + length : probe
                return
            }
            probe += 1
        }
        index = count
    }

    // MARK: - Markup (HTML, XML, plists)

    private func scanMarkup() {
        var inTag = false
        while let scalar = current {
            let start = index
            if !inTag {
                if matches("<!--") {
                    consumeUntil("-->", including: true)
                    emit(.comment, from: start)
                } else if scalar == "<", let next = peek(), next == "!" || next == "?" {
                    consumeUntil(">", including: true)
                    emit(.meta, from: start)
                } else if scalar == "<", let next = peek(), next.isIdentifierStart || next == "/" {
                    index += 1
                    emit(.punctuation, from: start)
                    if current == "/" {
                        let slash = index
                        index += 1
                        emit(.punctuation, from: slash)
                    }
                    let name = index
                    index = identifierEnd(from: name)
                    emit(.name, from: name)
                    inTag = true
                } else {
                    while let inner = current, inner != "<" { index += 1 }
                    emit(.plain, from: start)
                }
            } else {
                if scalar == ">" {
                    index += 1
                    emit(.punctuation, from: start)
                    inTag = false
                } else if scalar == "/" && peek() == ">" {
                    index += 1
                    emit(.punctuation, from: start)
                } else if scalar == "=" {
                    index += 1
                    emit(.operatorSymbol, from: start)
                } else if scalar == "\"" || scalar == "'" {
                    consumeQuoted(scalar)
                    emit(.string, from: start)
                } else if scalar.isIdentifierStart {
                    index = identifierEnd(from: start)
                    emit(.attribute, from: start)
                } else if scalar.isWhitespace {
                    index = whitespaceEnd(from: start)
                    emit(.plain, from: start)
                } else {
                    index += 1
                    emit(.plain, from: start)
                }
            }
        }
    }

    // MARK: - Stylesheets (CSS, SCSS, Less)

    private func scanStylesheet() {
        var depth = 0
        var expectProperty = true
        while let scalar = current {
            let start = index
            if scalar.isWhitespace {
                index = whitespaceEnd(from: start)
                emit(.plain, from: start)
            } else if matches("/*") {
                consumeUntil("*/", including: true)
                emit(.comment, from: start)
            } else if matches("//") {
                consumeLine()
                emit(.comment, from: start)
            } else if scalar == "{" || scalar == "}" || scalar == ";" {
                if scalar == "{" {
                    depth += 1
                } else if scalar == "}" {
                    depth = max(0, depth - 1)
                }
                expectProperty = true
                index += 1
                emit(.punctuation, from: start)
            } else if scalar == ":" {
                index += 1
                if depth == 0 {
                    // Pseudo-class selector outside a rule.
                    if current == ":" { index += 1 }
                    index = cssIdentifierEnd(from: index)
                    emit(.keyword, from: start)
                } else {
                    expectProperty = false
                    emit(.punctuation, from: start)
                }
            } else if scalar == "@" {
                index = cssIdentifierEnd(from: start + 1)
                emit(.meta, from: start)
            } else if scalar == "$" {
                index = cssIdentifierEnd(from: start + 1)
                emit(.variable, from: start)
            } else if scalar == "#" {
                if depth > 0, let next = peek(), next.isHexDigit {
                    index = numberEnd(from: start + 1)
                    emit(.number, from: start)
                } else {
                    index = cssIdentifierEnd(from: start + 1)
                    emit(.type, from: start)
                }
            } else if scalar == "." {
                index = cssIdentifierEnd(from: start + 1)
                emit(.type, from: start)
            } else if scalar == "\"" || scalar == "'" {
                consumeQuoted(scalar)
                emit(.string, from: start)
            } else if scalar == "!" {
                index = cssIdentifierEnd(from: start + 1)
                emit(.keyword, from: start)
            } else if scalar.isASCIIDigit || ("-+.".unicodeScalars.contains(scalar) && peek()?.isASCIIDigit == true) {
                index = numberEnd(from: start)
                if current == "%" { index += 1 }
                emit(.number, from: start)
            } else if scalar == "%" {
                index += 1
                emit(.number, from: start)
            } else if scalar.isIdentifierStart || (scalar == "-" && peek()?.isIdentifierContinue == true) {
                index = cssIdentifierEnd(from: start)
                let name = text(start, index).lowercased()
                if depth == 0 {
                    emit(["and", "not", "only", "from", "to"].contains(name) ? .keyword : .tag, from: start)
                } else if expectProperty {
                    emit(.property, from: start)
                } else if isFollowedByCall() {
                    emit(.function, from: start)
                } else {
                    emit(["inherit", "initial", "unset", "revert"].contains(name) ? .keyword : .plain, from: start)
                }
            } else if "()[]{}".unicodeScalars.contains(scalar) || scalar == "," {
                index += 1
                emit(.punctuation, from: start)
            } else {
                index += 1
                emit(.operatorSymbol, from: start)
            }
        }
    }

    // MARK: - Markdown

    private func scanMarkdown() {
        var inFence = false
        while let scalar = current {
            let lineStart = index
            consumeLine()
            let lineEnd = index
            let indent = leadingSpaces(from: lineStart, to: lineEnd)
            let bodyStart = lineStart + indent
            let body = text(bodyStart, lineEnd)
            if body.hasPrefix("```") || body.hasPrefix("~~~") {
                inFence.toggle()
                emit(.meta, from: lineStart, to: lineEnd)
            } else if inFence {
                emit(.code, from: lineStart, to: lineEnd)
            } else if isHeading(body) {
                emit(.section, from: lineStart, to: lineEnd, bold: true)
            } else if isRule(body) {
                emit(.meta, from: lineStart, to: lineEnd)
            } else if body.hasPrefix(">") {
                emit(.plain, from: lineStart, to: bodyStart)
                emit(.quote, from: bodyStart, to: bodyStart + 1)
                scanInlineMarkdown(from: bodyStart + 1, to: lineEnd)
            } else if let markerLength = listMarkerLength(body) {
                emit(.plain, from: lineStart, to: bodyStart)
                emit(.bullet, from: bodyStart, to: bodyStart + markerLength)
                scanInlineMarkdown(from: bodyStart + markerLength, to: lineEnd)
            } else {
                scanInlineMarkdown(from: lineStart, to: lineEnd)
            }
            if scalar == "\n" {
                index += 1
                emit(.plain, from: lineEnd)
            }
        }
    }

    private func leadingSpaces(from start: Int, to end: Int) -> Int {
        var position = start
        while position < end, scalars[position] == " " || scalars[position] == "\t" { position += 1 }
        return position - start
    }

    private func isHeading(_ body: String) -> Bool {
        var hashes = 0
        for character in body {
            if character == "#" { hashes += 1 } else { break }
        }
        guard (1...6).contains(hashes) else { return false }
        let after = body.drop { $0 == "#" }
        return after.isEmpty || after.first == " "
    }

    private func isRule(_ body: String) -> Bool {
        let compact = body.filter { $0 != " " && $0 != "\t" }
        guard let first = compact.first, "-*_".contains(first), compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == first }
    }

    /// Length of a `-`, `*`, `+` or `1.` list marker at the start of `body`.
    private func listMarkerLength(_ body: String) -> Int? {
        if let first = body.first, "-*+".contains(first) {
            return body.dropFirst().first == " " ? 1 : nil
        }
        var digits = 0
        for character in body {
            if character.isNumber { digits += 1 } else { break }
        }
        guard digits > 0 else { return nil }
        let rest = body.dropFirst(digits)
        guard let stop = rest.first, stop == "." || stop == ")", rest.dropFirst().first == " " else { return nil }
        return digits + 1
    }

    /// Inline code, emphasis and links within one line.
    private func scanInlineMarkdown(from start: Int, to end: Int) {
        var position = start
        while position < end {
            let runStart = position
            let scalar = scalars[position]
            switch scalar {
            case "`":
                if let close = findScalar("`", from: position + 1, to: end) {
                    position = close + 1
                    emit(.code, from: runStart, to: position)
                } else {
                    position += 1
                    emit(.plain, from: runStart, to: position)
                }
            case "*", "_":
                let doubled = scalar == "*" && scalarAt(position + 1) == "*"
                let width = doubled ? 2 : 1
                if let close = findEmphasisClose(scalar, width: width, from: position + width, to: end) {
                    position = close + width
                    emit(.plain, from: runStart, to: position, bold: doubled, italic: !doubled)
                } else {
                    position += 1
                    emit(.plain, from: runStart, to: position)
                }
            case "[":
                if let close = findLink(from: position, to: end) {
                    emit(.link, from: runStart, to: close.bracket + 1)
                    emit(.attribute, from: close.bracket + 1, to: close.paren + 1)
                    position = close.paren + 1
                } else {
                    position += 1
                    emit(.plain, from: runStart, to: position)
                }
            default:
                while position < end, !"`*_[".unicodeScalars.contains(scalars[position]) { position += 1 }
                emit(.plain, from: runStart, to: position)
            }
        }
    }

    private func findScalar(_ needle: Unicode.Scalar, from: Int, to: Int) -> Int? {
        var position = from
        while position < to {
            if scalars[position] == needle { return position }
            position += 1
        }
        return nil
    }

    /// Closing `*` / `**` / `_` not preceded by a space (and not running
    /// into another marker); `_` also needs a word boundary before the
    /// opening marker.
    private func findEmphasisClose(_ marker: Unicode.Scalar, width: Int, from: Int, to: Int) -> Int? {
        guard from < to, scalars[from] != " " else { return nil }
        if marker == "_", let before = scalarAt(from - width - 1), before.isIdentifierContinue { return nil }
        var position = from
        while position + width <= to {
            if scalars[position] == marker, scalars[position - 1] != " ",
               width == 1 || scalars[position + 1] == marker,
               scalarAt(position + width) != marker {
                return position
            }
            position += 1
        }
        return nil
    }

    /// `[text](url)` → the indices of `] ` and `)`.
    private func findLink(from start: Int, to end: Int) -> (bracket: Int, paren: Int)? {
        guard let bracket = findScalar("]", from: start + 1, to: end),
              scalarAt(bracket + 1) == "(",
              let paren = findScalar(")", from: bracket + 2, to: end) else { return nil }
        return (bracket, paren)
    }

    // MARK: - JSON

    private func scanJSON() {
        while let scalar = current {
            let start = index
            if scalar.isWhitespace {
                index = whitespaceEnd(from: start)
                emit(.plain, from: start)
            } else if scalar == "\"" {
                consumeQuoted(scalar)
                // A string followed by a colon is a key.
                var probe = index
                while let inner = scalarAt(probe), inner == " " || inner == "\t" || inner == "\n" { probe += 1 }
                emit(scalarAt(probe) == ":" ? .attribute : .string, from: start)
            } else if scalar.isASCIIDigit || scalar == "-" {
                index = numberEnd(from: start)
                emit(.number, from: start)
            } else if scalar.isIdentifierStart {
                index = identifierEnd(from: start)
                emit(["true", "false", "null"].contains(text(start, index)) ? .literal : .plain, from: start)
            } else if "{}[],:".unicodeScalars.contains(scalar) {
                index += 1
                emit(.punctuation, from: start)
            } else {
                index += 1
                emit(.plain, from: start)
            }
        }
    }

    // MARK: - YAML

    private func scanYAML() {
        // Indent of an open `|` / `>` block; deeper lines are literal text.
        var literalIndent: Int? = nil
        while let scalar = current {
            let lineStart = index
            consumeLine()
            let lineEnd = index
            let indent = leadingSpaces(from: lineStart, to: lineEnd)
            let isBlank = lineStart + indent == lineEnd
            if let open = literalIndent, isBlank || indent > open {
                emit(.string, from: lineStart, to: lineEnd)
            } else {
                literalIndent = scanYAMLLine(from: lineStart, to: lineEnd, indent: indent)
            }
            if scalar == "\n" {
                index += 1
                emit(.plain, from: lineEnd)
            }
        }
    }

    /// Styles one line; returns the indent when the line opens a literal block.
    private func scanYAMLLine(from start: Int, to end: Int, indent: Int) -> Int? {
        var position = start + indent
        emit(.plain, from: start, to: position)
        if position < end, scalars[position] == "#" {
            emit(.comment, from: position, to: end)
            return nil
        }
        let rest = text(position, end)
        if rest == "---" || rest == "..." || rest.hasPrefix("%YAML") || rest.hasPrefix("%TAG") {
            emit(.meta, from: position, to: end)
            return nil
        }
        if scalarAt(position) == "-", scalarAt(position + 1) == " " || scalarAt(position + 1) == "\t" {
            emit(.bullet, from: position, to: position + 1)
            position += 1
        }
        if let key = yamlKeyEnd(from: position, to: end) {
            emit(.attribute, from: position, to: key)
            emit(.punctuation, from: key, to: key + 1)
            position = key + 1
        }
        return scanYAMLValue(from: position, to: end, indent: indent)
    }

    /// Index of the `:` ending a mapping key (quoted or plain), or nil.
    private func yamlKeyEnd(from start: Int, to end: Int) -> Int? {
        guard let first = scalarAt(start) else { return nil }
        if first == "\"" || first == "'" {
            var position = start + 1
            while position < end, scalars[position] != first { position += 1 }
            guard position < end else { return nil }
            var after = position + 1
            while after < end, scalars[after] == " " { after += 1 }
            return scalarAt(after) == ":" ? after : nil
        }
        var position = start
        while position < end {
            let scalar = scalars[position]
            if scalar == "#", position > start, scalars[position - 1] == " " { return nil }
            if scalar == ":", position + 1 == end || scalars[position + 1] == " " || scalars[position + 1] == "\t" {
                return position
            }
            position += 1
        }
        return nil
    }

    private func scanYAMLValue(from start: Int, to end: Int, indent: Int) -> Int? {
        var position = start
        var literalIndent: Int? = nil
        while position < end {
            let scalar = scalars[position]
            let runStart = position
            switch scalar {
            case " ", "\t":
                while position < end, scalars[position] == " " || scalars[position] == "\t" { position += 1 }
                emit(.plain, from: runStart, to: position)
            case "#" where runStart == start || scalars[runStart - 1] == " ":
                emit(.comment, from: runStart, to: end)
                position = end
            case "&", "*":
                position = wordEnd(from: runStart + 1)
                emit(.variable, from: runStart, to: position)
            case "|", ">":
                while position < end, "|>+-".unicodeScalars.contains(scalars[position]) { position += 1 }
                if position == end { literalIndent = indent }
                emit(.meta, from: runStart, to: position)
            case "\"", "'":
                position += 1
                while position < end, scalars[position] != scalar { position += 1 }
                if position < end { position += 1 }
                emit(.string, from: runStart, to: position)
            case "[", "]", "{", "}", ",":
                position += 1
                emit(.punctuation, from: runStart, to: position)
            case "~":
                position += 1
                emit(.literal, from: runStart, to: position)
            default:
                if scalar.isASCIIDigit || ((scalar == "-" || scalar == "+" || scalar == ".") && scalarAt(position + 1)?.isASCIIDigit == true) {
                    position = numberEnd(from: runStart)
                    emit(.number, from: runStart, to: position)
                } else if scalar.isIdentifierStart {
                    position = wordEnd(from: runStart)
                    let word = text(runStart, position).lowercased()
                    let isLiteral = ["true", "false", "null", "yes", "no", "on", "off"].contains(word)
                    emit(isLiteral ? .literal : .plain, from: runStart, to: position)
                } else {
                    position += 1
                    emit(.plain, from: runStart, to: position)
                }
            }
        }
        return literalIndent
    }

    /// End of a plain scalar word (no spaces).
    private func wordEnd(from start: Int) -> Int {
        var position = start
        while let scalar = scalarAt(position), scalar.isIdentifierContinue || scalar == "-" || scalar == "/" || scalar == "." {
            position += 1
        }
        return max(position, start + 1)
    }

    // MARK: - INI / TOML

    private func scanINI() {
        while let scalar = current {
            let lineStart = index
            consumeLine()
            let lineEnd = index
            var position = lineStart
            while position < lineEnd, scalars[position] == " " || scalars[position] == "\t" { position += 1 }
            emit(.plain, from: lineStart, to: position)
            if position < lineEnd, scalars[position] == "#" || scalars[position] == ";" {
                emit(.comment, from: position, to: lineEnd)
            } else if position < lineEnd, scalars[position] == "[" {
                var close = position
                while close < lineEnd, scalars[close] != "]" { close += 1 }
                while close < lineEnd, scalars[close] == "]" { close += 1 }
                emit(.tag, from: position, to: close)
                let trailing = close
                while close < lineEnd, scalars[close] == " " || scalars[close] == "\t" { close += 1 }
                emit(.plain, from: trailing, to: close)
                if close < lineEnd, scalars[close] == "#" || scalars[close] == ";" {
                    emit(.comment, from: close, to: lineEnd)
                } else {
                    emit(.plain, from: close, to: lineEnd)
                }
            } else if let equals = (position..<lineEnd).first(where: { scalars[$0] == "=" }) {
                var keyEnd = equals
                while keyEnd > position, scalars[keyEnd - 1] == " " || scalars[keyEnd - 1] == "\t" { keyEnd -= 1 }
                emit(.attribute, from: position, to: keyEnd)
                emit(.plain, from: keyEnd, to: equals)
                emit(.operatorSymbol, from: equals, to: equals + 1)
                scanINIValue(from: equals + 1, to: lineEnd)
            } else {
                emit(.plain, from: position, to: lineEnd)
            }
            if scalar == "\n" {
                index += 1
                emit(.plain, from: lineEnd)
            }
        }
    }

    private func scanINIValue(from start: Int, to end: Int) {
        var position = start
        while position < end {
            let scalar = scalars[position]
            let runStart = position
            switch scalar {
            case " ", "\t":
                while position < end, scalars[position] == " " || scalars[position] == "\t" { position += 1 }
                emit(.plain, from: runStart, to: position)
            case "#" where runStart == start || scalars[runStart - 1] == " ",
                 ";" where runStart == start || scalars[runStart - 1] == " ":
                emit(.comment, from: runStart, to: end)
                position = end
            case "\"", "'":
                position += 1
                while position < end, scalars[position] != scalar { position += 1 }
                if position < end { position += 1 }
                emit(.string, from: runStart, to: position)
            case "[", "]", ",":
                position += 1
                emit(.punctuation, from: runStart, to: position)
            default:
                if scalar.isASCIIDigit || ((scalar == "-" || scalar == "+" || scalar == ".") && scalarAt(position + 1)?.isASCIIDigit == true) {
                    position = numberEnd(from: runStart)
                    emit(.number, from: runStart, to: position)
                } else if scalar.isIdentifierStart {
                    position = wordEnd(from: runStart)
                    let word = text(runStart, position).lowercased()
                    let isLiteral = ["true", "false", "yes", "no", "on", "off"].contains(word)
                    emit(isLiteral ? .literal : .plain, from: runStart, to: position)
                } else {
                    position += 1
                    emit(.plain, from: runStart, to: position)
                }
            }
        }
    }

    // MARK: - Diff

    private func scanDiff() {
        let metaPrefixes = ["diff ", "index ", "new file", "deleted file", "Binary files", "rename ",
                            "old mode", "new mode", "similarity index", "GIT binary patch"]
        while let scalar = current {
            let lineStart = index
            consumeLine()
            let lineEnd = index
            if lineEnd > lineStart {
                let line = text(lineStart, lineEnd)
                let kind: TokenKind
                switch line.first {
                case "+": kind = line.hasPrefix("+++") ? .meta : .added
                case "-": kind = line.hasPrefix("---") ? .meta : .removed
                case "@", "\\": kind = .meta
                default: kind = metaPrefixes.contains { line.hasPrefix($0) } ? .meta : .plain
                }
                emit(kind, from: lineStart, to: lineEnd)
            }
            if scalar == "\n" {
                index += 1
                emit(.plain, from: lineEnd)
            }
        }
    }
}

private extension Unicode.Scalar {
    var isWhitespace: Bool { properties.isWhitespace }
    var isASCIIDigit: Bool { value >= 0x30 && value <= 0x39 }
    var isASCIIAlphanumeric: Bool {
        (value >= 0x30 && value <= 0x39) || (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A)
    }
    var isHexDigit: Bool {
        isASCIIDigit || (value >= 0x61 && value <= 0x66) || (value >= 0x41 && value <= 0x46)
    }
    var isLetter: Bool { properties.isAlphabetic }
    /// Letters and `_`; any non-ASCII, non-space scalar qualifies too, so
    /// Unicode identifiers (`café`, emoji names) scan as one token.
    var isIdentifierStart: Bool {
        value < 0x80 ? isLetter || self == "_" : !isWhitespace
    }
    var isIdentifierContinue: Bool {
        value < 0x80 ? isLetter || isASCIIDigit || self == "_" : !isWhitespace
    }
    var isPunctuation: Bool { "()[]{},;.:".unicodeScalars.contains(self) }
    var isOperator: Bool { "=+-*/<>!&|^%~?@\\".unicodeScalars.contains(self) }
}
