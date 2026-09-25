/// Listes de mots-clés et built-ins pour l'autocomplétion par langage.
/// Chaque entrée est un mot qui peut être proposé lors de la saisie.
class LanguageCompletions {
  LanguageCompletions._();

  static const Map<String, List<String>> _data = {
    // ── Python ────────────────────────────────────────────────────────────────
    'python': [
      // Keywords
      'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await',
      'break', 'class', 'continue', 'def', 'del', 'elif', 'else', 'except',
      'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is',
      'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try',
      'while', 'with', 'yield',
      // Built-ins
      'abs', 'all', 'any', 'ascii', 'bin', 'bool', 'breakpoint', 'bytearray',
      'bytes', 'callable', 'chr', 'classmethod', 'compile', 'complex',
      'copyright', 'credits', 'delattr', 'dict', 'dir', 'divmod', 'enumerate',
      'eval', 'exec', 'exit', 'filter', 'float', 'format', 'frozenset',
      'getattr', 'globals', 'hasattr', 'hash', 'help', 'hex', 'id', 'input',
      'int', 'isinstance', 'issubclass', 'iter', 'len', 'list', 'locals',
      'map', 'max', 'memoryview', 'min', 'next', 'object', 'oct', 'open',
      'ord', 'pow', 'print', 'property', 'quit', 'range', 'repr', 'reversed',
      'round', 'set', 'setattr', 'slice', 'sorted', 'staticmethod', 'str',
      'sum', 'super', 'tuple', 'type', 'vars', 'zip',
      // Common stdlib
      'os', 'sys', 're', 'json', 'math', 'random', 'datetime', 'pathlib',
      'subprocess', 'threading', 'asyncio', 'typing', 'collections',
      'functools', 'itertools', 'contextlib', 'dataclasses', 'unittest',
      'logging', 'argparse', 'shutil', 'io', 'csv', 'sqlite3', 'urllib',
      'http', 'socket', 'struct', 'time', 'copy', 'pprint', 'pickle',
      // Decorators/patterns
      '__init__', '__str__', '__repr__', '__len__', '__getitem__', '__setitem__',
      '__contains__', '__iter__', '__next__', '__enter__', '__exit__',
      '__call__', '__eq__', '__lt__', '__gt__', '__add__', '__mul__',
      'self', 'cls', '__name__', '__main__', '__file__', '__doc__',
      // Popular libs
      'numpy', 'pandas', 'matplotlib', 'requests', 'flask', 'django',
      'pytest', 'pydantic', 'sqlalchemy', 'aiohttp', 'fastapi',
    ],

    // ── JavaScript / TypeScript ───────────────────────────────────────────────
    'javascript': [
      // Keywords
      'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
      'default', 'delete', 'do', 'else', 'export', 'extends', 'false',
      'finally', 'for', 'function', 'if', 'import', 'in', 'instanceof',
      'let', 'new', 'null', 'of', 'return', 'static', 'super', 'switch',
      'this', 'throw', 'true', 'try', 'typeof', 'undefined', 'var', 'void',
      'while', 'with', 'yield', 'async', 'await',
      // Built-ins
      'Array', 'Boolean', 'Date', 'Error', 'EvalError', 'Float32Array',
      'Float64Array', 'Function', 'Int8Array', 'Int16Array', 'Int32Array',
      'JSON', 'Map', 'Math', 'NaN', 'Number', 'Object', 'Promise',
      'Proxy', 'RangeError', 'ReferenceError', 'RegExp', 'Set', 'String',
      'Symbol', 'SyntaxError', 'TypeError', 'URIError', 'Uint8Array',
      'WeakMap', 'WeakSet', 'clearInterval', 'clearTimeout', 'console',
      'decodeURI', 'decodeURIComponent', 'encodeURI', 'encodeURIComponent',
      'eval', 'fetch', 'globalThis', 'isFinite', 'isNaN', 'parseFloat',
      'parseInt', 'setInterval', 'setTimeout', 'window', 'document',
      // Common patterns
      'constructor', 'prototype', 'valueOf', 'toString', 'hasOwnProperty',
      'forEach', 'map', 'filter', 'reduce', 'find', 'findIndex', 'includes',
      'indexOf', 'slice', 'splice', 'push', 'pop', 'shift', 'unshift',
      'join', 'split', 'replace', 'trim', 'toLowerCase', 'toUpperCase',
      'then', 'catch', 'finally', 'resolve', 'reject', 'all', 'race',
      // Node.js
      'require', 'module', 'exports', 'process', '__dirname', '__filename',
      'Buffer', 'path', 'fs', 'http', 'https', 'url', 'events', 'stream',
    ],

    // TypeScript = JavaScript + type keywords
    'typescript': [
      'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
      'default', 'delete', 'do', 'else', 'export', 'extends', 'false',
      'finally', 'for', 'function', 'if', 'import', 'in', 'instanceof',
      'let', 'new', 'null', 'of', 'return', 'static', 'super', 'switch',
      'this', 'throw', 'true', 'try', 'typeof', 'undefined', 'var', 'void',
      'while', 'with', 'yield', 'async', 'await',
      // TS-specific
      'abstract', 'as', 'declare', 'enum', 'implements', 'interface',
      'module', 'namespace', 'never', 'override', 'private', 'protected',
      'public', 'readonly', 'satisfies', 'type', 'keyof', 'infer',
      'unknown', 'any', 'boolean', 'number', 'string', 'object',
      'symbol', 'bigint', 'Partial', 'Required', 'Readonly', 'Record',
      'Pick', 'Omit', 'Exclude', 'Extract', 'NonNullable', 'ReturnType',
      'InstanceType', 'Parameters', 'ConstructorParameters', 'Awaited',
    ],

    // ── Dart ─────────────────────────────────────────────────────────────────
    'dart': [
      // Keywords
      'abstract', 'as', 'assert', 'async', 'await', 'base', 'break',
      'case', 'catch', 'class', 'const', 'continue', 'covariant', 'default',
      'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends',
      'extension', 'external', 'factory', 'false', 'final', 'finally',
      'for', 'function', 'get', 'hide', 'if', 'implements', 'import',
      'in', 'interface', 'is', 'late', 'library', 'mixin', 'new', 'null',
      'of', 'on', 'operator', 'part', 'required', 'rethrow', 'return',
      'sealed', 'set', 'show', 'static', 'super', 'switch', 'sync', 'this',
      'throw', 'true', 'try', 'typedef', 'var', 'void', 'when', 'while',
      'with', 'yield',
      // Types
      'bool', 'double', 'int', 'num', 'String', 'List', 'Map', 'Set',
      'Iterable', 'Future', 'Stream', 'Object', 'Never', 'Null', 'Symbol',
      'Type', 'Function', 'Duration', 'DateTime', 'Uri', 'BigInt',
      'Uint8List', 'ByteData', 'RegExp', 'Comparable', 'Pattern',
      // Flutter
      'Widget', 'StatefulWidget', 'StatelessWidget', 'BuildContext',
      'State', 'Key', 'UniqueKey', 'ValueKey', 'GlobalKey',
      'Scaffold', 'AppBar', 'Container', 'Row', 'Column', 'Stack', 'Expanded',
      'Flexible', 'Padding', 'SizedBox', 'Center', 'Align', 'Text', 'Icon',
      'Image', 'ListView', 'GridView', 'SingleChildScrollView', 'Scrollbar',
      'GestureDetector', 'InkWell', 'TextButton', 'ElevatedButton',
      'FilledButton', 'OutlinedButton', 'IconButton', 'FloatingActionButton',
      'TextField', 'TextEditingController', 'FocusNode', 'Navigator',
      'MaterialApp', 'Material', 'Theme', 'ThemeData', 'Colors', 'Color',
      'TextStyle', 'FontWeight', 'FontStyle', 'EdgeInsets', 'BorderRadius',
      'BoxDecoration', 'BoxShadow', 'Offset', 'Size', 'Rect', 'MediaQuery',
      'SafeArea', 'Opacity', 'AnimatedContainer', 'AnimationController',
      'ChangeNotifier', 'Provider', 'Consumer', 'context', 'setState',
      'initState', 'dispose', 'build', 'mounted', 'widget', 'super',
      'override', 'const', 'final', 'late',
      // Dart stdlib
      'print', 'identical', 'hashCode', 'toString', 'runtimeType',
      'jsonDecode', 'jsonEncode', 'File', 'Directory', 'Process',
      'Platform', 'path', 'basename', 'dirname', 'extension', 'join',
    ],

    // ── Java ─────────────────────────────────────────────────────────────────
    'java': [
      'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch',
      'char', 'class', 'const', 'continue', 'default', 'do', 'double',
      'else', 'enum', 'extends', 'final', 'finally', 'float', 'for', 'goto',
      'if', 'implements', 'import', 'instanceof', 'int', 'interface', 'long',
      'native', 'new', 'null', 'package', 'private', 'protected', 'public',
      'return', 'short', 'static', 'strictfp', 'super', 'switch', 'synchronized',
      'this', 'throw', 'throws', 'transient', 'true', 'try', 'var', 'void',
      'volatile', 'while', 'record', 'sealed', 'permits', 'yield', 'text',
      // Common classes
      'String', 'Integer', 'Long', 'Double', 'Float', 'Boolean', 'Byte',
      'Character', 'Short', 'Object', 'Class', 'System', 'Math', 'Arrays',
      'Collections', 'List', 'ArrayList', 'LinkedList', 'Map', 'HashMap',
      'LinkedHashMap', 'TreeMap', 'Set', 'HashSet', 'TreeSet', 'Queue',
      'Stack', 'Optional', 'Stream', 'Collectors', 'Iterator', 'Iterable',
      'Comparable', 'Comparator', 'StringBuilder', 'StringBuffer',
      'Thread', 'Runnable', 'Callable', 'Future', 'CompletableFuture',
      'Exception', 'RuntimeException', 'NullPointerException', 'IOException',
      'IllegalArgumentException', 'IllegalStateException',
      'Override', 'Deprecated', 'SuppressWarnings', 'FunctionalInterface',
      'println', 'printf', 'format', 'valueOf', 'parseInt', 'toString',
      'equals', 'hashCode', 'compareTo', 'length', 'size', 'isEmpty',
      'get', 'set', 'add', 'remove', 'contains', 'put', 'clear',
    ],

    // ── Kotlin ───────────────────────────────────────────────────────────────
    'kotlin': [
      'abstract', 'actual', 'annotation', 'as', 'break', 'by', 'catch',
      'class', 'companion', 'const', 'constructor', 'continue', 'crossinline',
      'data', 'do', 'dynamic', 'else', 'enum', 'expect', 'external', 'false',
      'final', 'finally', 'for', 'fun', 'if', 'import', 'in', 'infix',
      'init', 'inline', 'inner', 'interface', 'internal', 'is', 'it',
      'lateinit', 'noinline', 'null', 'object', 'open', 'operator', 'out',
      'override', 'package', 'private', 'protected', 'public', 'reified',
      'return', 'sealed', 'super', 'suspend', 'tailrec', 'this', 'throw',
      'true', 'try', 'typealias', 'typeof', 'val', 'var', 'vararg', 'when',
      'where', 'while',
      // Types & stdlib
      'Any', 'Array', 'Boolean', 'Byte', 'Char', 'Double', 'Float', 'Int',
      'Long', 'Nothing', 'Number', 'Short', 'String', 'Unit', 'List', 'Map',
      'Set', 'MutableList', 'MutableMap', 'MutableSet', 'Sequence', 'Flow',
      'Pair', 'Triple', 'Result', 'Deferred', 'Job', 'CoroutineScope',
      'launch', 'async', 'await', 'runBlocking', 'withContext', 'delay',
      'let', 'run', 'also', 'apply', 'with', 'takeIf', 'takeUnless',
      'println', 'print', 'readLine', 'TODO', 'error', 'check', 'require',
      'listOf', 'mapOf', 'setOf', 'mutableListOf', 'mutableMapOf',
      'arrayOf', 'arrayListOf', 'emptyList', 'emptyMap', 'emptySet',
      'first', 'last', 'filter', 'map', 'flatMap', 'forEach', 'fold',
      'reduce', 'groupBy', 'sortedBy', 'distinctBy', 'maxByOrNull',
    ],

    // ── C / C++ ──────────────────────────────────────────────────────────────
    'cpp': [
      // C keywords
      'auto', 'break', 'case', 'char', 'const', 'continue', 'default',
      'do', 'double', 'else', 'enum', 'extern', 'float', 'for', 'goto',
      'if', 'inline', 'int', 'long', 'register', 'restrict', 'return',
      'short', 'signed', 'sizeof', 'static', 'struct', 'switch', 'typedef',
      'union', 'unsigned', 'void', 'volatile', 'while',
      // C++ keywords
      'alignas', 'alignof', 'and', 'and_eq', 'asm', 'bitand', 'bitor',
      'bool', 'catch', 'class', 'compl', 'concept', 'consteval', 'constexpr',
      'constinit', 'co_await', 'co_return', 'co_yield', 'decltype', 'delete',
      'dynamic_cast', 'explicit', 'export', 'false', 'friend', 'module',
      'mutable', 'namespace', 'new', 'noexcept', 'not', 'not_eq', 'nullptr',
      'operator', 'or', 'or_eq', 'private', 'protected', 'public',
      'reinterpret_cast', 'requires', 'static_assert', 'static_cast',
      'template', 'this', 'thread_local', 'throw', 'true', 'try', 'typeid',
      'typename', 'using', 'virtual', 'wchar_t', 'xor', 'xor_eq', 'override',
      'final',
      // STL & common
      'std', 'string', 'vector', 'map', 'set', 'unordered_map',
      'unordered_set', 'list', 'deque', 'queue', 'stack', 'array',
      'pair', 'tuple', 'optional', 'variant', 'any', 'function',
      'shared_ptr', 'unique_ptr', 'weak_ptr', 'make_shared', 'make_unique',
      'move', 'forward', 'swap', 'sort', 'find', 'copy', 'fill', 'count',
      'begin', 'end', 'size', 'empty', 'push_back', 'pop_back', 'emplace',
      'cout', 'cin', 'cerr', 'endl', 'printf', 'scanf', 'malloc', 'free',
      'NULL', 'nullptr', 'INT_MAX', 'INT_MIN', 'UINT_MAX', 'SIZE_MAX',
      '#include', '#define', '#ifdef', '#ifndef', '#endif', '#pragma', '#if',
    ],

    // ── Rust ─────────────────────────────────────────────────────────────────
    'rust': [
      'as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'do',
      'dyn', 'else', 'enum', 'extern', 'false', 'fn', 'for', 'if', 'impl',
      'in', 'let', 'loop', 'match', 'mod', 'move', 'mut', 'pub', 'ref',
      'return', 'self', 'Self', 'static', 'struct', 'super', 'trait', 'true',
      'type', 'union', 'unsafe', 'use', 'where', 'while',
      // Types
      'bool', 'char', 'f32', 'f64', 'i8', 'i16', 'i32', 'i64', 'i128',
      'isize', 'u8', 'u16', 'u32', 'u64', 'u128', 'usize', 'str', 'String',
      'Vec', 'HashMap', 'HashSet', 'BTreeMap', 'BTreeSet', 'Option', 'Result',
      'Box', 'Rc', 'Arc', 'Cell', 'RefCell', 'Mutex', 'RwLock',
      'Ok', 'Err', 'Some', 'None', 'Default', 'Clone', 'Copy', 'Debug',
      'Display', 'PartialEq', 'Eq', 'Hash', 'Ord', 'PartialOrd',
      'From', 'Into', 'AsRef', 'AsMut', 'Deref', 'DerefMut', 'Drop',
      'Iterator', 'IntoIterator', 'Index', 'IndexMut', 'Add', 'Sub',
      'println!', 'print!', 'eprintln!', 'panic!', 'assert!', 'assert_eq!',
      'assert_ne!', 'todo!', 'unimplemented!', 'unreachable!', 'vec!',
      'format!', 'write!', 'writeln!', 'dbg!', 'include!', 'include_str!',
      'unwrap', 'expect', 'ok', 'err', 'map', 'and_then', 'or_else',
      'is_some', 'is_none', 'is_ok', 'is_err', 'unwrap_or', 'unwrap_or_else',
      'len', 'is_empty', 'push', 'pop', 'insert', 'remove', 'get', 'iter',
    ],

    // ── Go ───────────────────────────────────────────────────────────────────
    'go': [
      'break', 'case', 'chan', 'const', 'continue', 'default', 'defer',
      'else', 'fallthrough', 'for', 'func', 'go', 'goto', 'if', 'import',
      'interface', 'map', 'package', 'range', 'return', 'select', 'struct',
      'switch', 'type', 'var',
      // Built-in
      'bool', 'byte', 'complex64', 'complex128', 'error', 'float32', 'float64',
      'int', 'int8', 'int16', 'int32', 'int64', 'rune', 'string', 'uint',
      'uint8', 'uint16', 'uint32', 'uint64', 'uintptr', 'any', 'comparable',
      'true', 'false', 'nil', 'iota',
      'append', 'cap', 'clear', 'close', 'complex', 'copy', 'delete', 'imag',
      'len', 'make', 'max', 'min', 'new', 'panic', 'print', 'println',
      'real', 'recover',
      // stdlib
      'fmt', 'log', 'os', 'io', 'bufio', 'strings', 'strconv', 'bytes',
      'math', 'sort', 'sync', 'time', 'context', 'errors', 'encoding',
      'json', 'http', 'url', 'net', 'path', 'filepath', 'testing',
      'Println', 'Printf', 'Fprintf', 'Sprintf', 'Errorf', 'Scan', 'Sscanf',
    ],

    // ── HTML ─────────────────────────────────────────────────────────────────
    'html': [
      // Tags
      'html', 'head', 'title', 'base', 'link', 'meta', 'style', 'script',
      'body', 'header', 'footer', 'main', 'nav', 'aside', 'section',
      'article', 'address', 'div', 'span', 'h1', 'h2', 'h3', 'h4', 'h5',
      'h6', 'p', 'hr', 'br', 'pre', 'blockquote', 'ol', 'ul', 'li', 'dl',
      'dt', 'dd', 'figure', 'figcaption', 'a', 'abbr', 'b', 'bdi', 'bdo',
      'cite', 'code', 'data', 'dfn', 'em', 'i', 'kbd', 'mark', 'q', 'rp',
      'rt', 'ruby', 's', 'samp', 'small', 'strong', 'sub', 'sup', 'time',
      'u', 'var', 'wbr', 'area', 'audio', 'img', 'map', 'track', 'video',
      'embed', 'iframe', 'object', 'param', 'picture', 'source', 'canvas',
      'noscript', 'del', 'ins', 'caption', 'col', 'colgroup', 'table',
      'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'button', 'datalist',
      'fieldset', 'form', 'input', 'label', 'legend', 'meter', 'optgroup',
      'option', 'output', 'progress', 'select', 'textarea', 'details',
      'dialog', 'summary', 'slot', 'template',
      // Attributes
      'class', 'id', 'style', 'href', 'src', 'alt', 'title', 'type', 'name',
      'value', 'placeholder', 'required', 'disabled', 'readonly', 'checked',
      'selected', 'multiple', 'target', 'rel', 'action', 'method', 'enctype',
      'for', 'data-', 'aria-label', 'aria-hidden', 'role', 'tabindex',
      'width', 'height', 'lang', 'charset', 'content', 'viewport',
    ],

    // ── XML ──────────────────────────────────────────────────────────────────
    'xml': [
      // Common declarations and structures
      'xml', 'version', 'encoding', 'standalone', 'DOCTYPE', 'element',
      'attlist', 'entity', 'notation', 'cdata', 'xsl', 'stylesheet',
      'template', 'value-of', 'for-each', 'if', 'choose', 'when', 'otherwise',
      'call-template', 'param', 'with-param', 'variable', 'apply-templates',
    ],

    // ── CSS ──────────────────────────────────────────────────────────────────
    'css': [
      // Properties
      'align-content', 'align-items', 'align-self', 'animation', 'aspect-ratio',
      'background', 'background-color', 'background-image', 'background-position',
      'background-repeat', 'background-size', 'border', 'border-radius',
      'border-color', 'border-style', 'border-width', 'bottom', 'box-shadow',
      'box-sizing', 'color', 'columns', 'content', 'cursor', 'display',
      'filter', 'flex', 'flex-direction', 'flex-wrap', 'flex-flow',
      'flex-grow', 'flex-shrink', 'float', 'font', 'font-family',
      'font-size', 'font-style', 'font-weight', 'gap', 'grid', 'grid-area',
      'grid-column', 'grid-row', 'grid-template', 'grid-template-columns',
      'grid-template-rows', 'height', 'justify-content', 'justify-items',
      'left', 'letter-spacing', 'line-height', 'list-style', 'margin',
      'max-height', 'max-width', 'min-height', 'min-width', 'object-fit',
      'opacity', 'order', 'outline', 'overflow', 'padding', 'position',
      'right', 'text-align', 'text-decoration', 'text-shadow', 'text-transform',
      'top', 'transform', 'transition', 'user-select', 'vertical-align',
      'visibility', 'white-space', 'width', 'word-break', 'z-index',
      // Values
      'none', 'auto', 'inherit', 'initial', 'unset', 'revert',
      'flex', 'grid', 'block', 'inline', 'inline-block', 'inline-flex',
      'relative', 'absolute', 'fixed', 'sticky', 'static',
      'bold', 'normal', 'italic', 'underline', 'center', 'left', 'right',
      'top', 'bottom', 'middle', 'baseline', 'stretch', 'nowrap',
      'pointer', 'default', 'grab', 'grabbing', 'crosshair', 'text',
      'hidden', 'visible', 'scroll', 'clip', 'ellipsis',
      'solid', 'dashed', 'dotted', 'double',
      'ease', 'ease-in', 'ease-out', 'ease-in-out', 'linear',
      'var(', 'calc(', 'rgb(', 'rgba(', 'hsl(', 'hsla(', 'url(',
      'px', 'em', 'rem', 'vh', 'vw', 'vmin', 'vmax', '%',
      // Selectors/at-rules
      '@media', '@keyframes', '@import', '@font-face', '@supports', '@layer',
      ':hover', ':focus', ':active', ':visited', ':first-child', ':last-child',
      ':nth-child(', ':not(', ':is(', ':where(', ':has(',
      '::before', '::after', '::placeholder', '::selection',
    ],

    // ── SQL ──────────────────────────────────────────────────────────────────
    'sql': [
      'SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'IN', 'BETWEEN',
      'LIKE', 'IS', 'NULL', 'ORDER', 'BY', 'ASC', 'DESC', 'LIMIT', 'OFFSET',
      'GROUP', 'HAVING', 'JOIN', 'INNER', 'LEFT', 'RIGHT', 'FULL', 'OUTER',
      'CROSS', 'ON', 'UNION', 'INTERSECT', 'EXCEPT', 'ALL', 'DISTINCT',
      'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'CREATE',
      'TABLE', 'VIEW', 'INDEX', 'TRIGGER', 'PROCEDURE', 'FUNCTION', 'SCHEMA',
      'DATABASE', 'DROP', 'ALTER', 'ADD', 'COLUMN', 'RENAME', 'MODIFY',
      'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES', 'UNIQUE', 'CHECK',
      'DEFAULT', 'AUTO_INCREMENT', 'SERIAL', 'CONSTRAINT', 'CASCADE',
      'RESTRICT', 'TRANSACTION', 'COMMIT', 'ROLLBACK', 'BEGIN', 'SAVEPOINT',
      'GRANT', 'REVOKE', 'EXPLAIN', 'ANALYZE', 'VACUUM', 'TRUNCATE',
      'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'COALESCE', 'NULLIF', 'CASE',
      'WHEN', 'THEN', 'ELSE', 'END', 'EXISTS', 'ANY', 'SOME', 'AS',
      'WITH', 'RECURSIVE', 'OVER', 'PARTITION', 'ROW_NUMBER', 'RANK',
      'DENSE_RANK', 'LAG', 'LEAD', 'FIRST_VALUE', 'LAST_VALUE',
      'INT', 'INTEGER', 'BIGINT', 'SMALLINT', 'DECIMAL', 'NUMERIC',
      'FLOAT', 'DOUBLE', 'REAL', 'VARCHAR', 'CHAR', 'TEXT', 'BOOLEAN',
      'DATE', 'TIME', 'DATETIME', 'TIMESTAMP', 'BLOB', 'JSON', 'ARRAY',
      'NOW()', 'CURRENT_TIMESTAMP', 'CURRENT_DATE', 'CURRENT_TIME',
      'CONCAT', 'SUBSTRING', 'LENGTH', 'TRIM', 'UPPER', 'LOWER',
      'REPLACE', 'CAST', 'CONVERT', 'IF', 'IFNULL', 'IIF',
    ],

    // ── Shell / Bash ─────────────────────────────────────────────────────────
    'bash': [
      // Builtins
      'alias', 'bg', 'bind', 'break', 'builtin', 'caller', 'cd', 'command',
      'compgen', 'complete', 'compopt', 'continue', 'declare', 'dirs',
      'disown', 'echo', 'enable', 'eval', 'exec', 'exit', 'export', 'false',
      'fc', 'fg', 'getopts', 'hash', 'help', 'history', 'jobs', 'kill',
      'let', 'local', 'logout', 'mapfile', 'popd', 'printf', 'pushd',
      'pwd', 'read', 'readarray', 'readonly', 'return', 'set', 'shift',
      'shopt', 'source', 'suspend', 'test', 'times', 'trap', 'true', 'type',
      'typeset', 'ulimit', 'umask', 'unalias', 'unset', 'wait',
      // Control
      'if', 'then', 'else', 'elif', 'fi', 'case', 'esac', 'for', 'while',
      'until', 'do', 'done', 'select', 'in', 'function',
      // Common commands
      'ls', 'cat', 'grep', 'sed', 'awk', 'find', 'xargs', 'sort', 'uniq',
      'cut', 'paste', 'head', 'tail', 'wc', 'tr', 'mv', 'cp', 'rm', 'mkdir',
      'rmdir', 'touch', 'chmod', 'chown', 'ln', 'tar', 'gzip', 'bzip2',
      'curl', 'wget', 'ssh', 'scp', 'rsync', 'git', 'make', 'cmake',
      'apt', 'apt-get', 'dnf', 'yum', 'pacman', 'brew', 'pip', 'npm',
      'python3', 'python', 'node', 'java', 'javac', 'gcc', 'g++', 'rustc',
      'cargo', 'go', 'dart', 'flutter', 'docker', 'kubectl', 'terraform',
      // Variables
      r'$0', r'$1', r'$2', r'$@', r'$*', r'$#', r'$?', r'$$', r'$!', r'$-',
      'HOME', 'PATH', 'USER', 'PWD', 'OLDPWD', 'SHELL', 'TERM', 'EDITOR',
    ],

    // ── Markdown ─────────────────────────────────────────────────────────────
    'markdown': [
      '# ', '## ', '### ', '#### ', '##### ', '###### ',
      '**bold**', '_italic_', '~~strikethrough~~', '`code`',
      '```', '> ', '- ', '* ', '1. ', '- [ ] ', '- [x] ',
      '[text](url)', '![alt](url)', '---', '===',
      '| Column | Column |', '|--------|--------|',
    ],
  };

  // ── Patterns d'extraction de symboles par langage ─────────────────────────

  /// Patterns regex pour extraire les noms de fonctions, classes, variables.
  static const Map<String, List<String>> _symbolPatterns = {
    'python': [
      r'def\s+(\w+)\s*\(',         // fonctions
      r'class\s+(\w+)\s*[:(]',     // classes
      r'^(\w+)\s*=\s*',            // variables globales
    ],
    'javascript': [
      r'function\s+(\w+)\s*\(',
      r'(?:const|let|var)\s+(\w+)\s*=\s*(?:function|\(.*\)\s*=>)',
      r'class\s+(\w+)\s*{',
      r'(?:const|let|var)\s+(\w+)\s*=',
    ],
    'typescript': [
      r'function\s+(\w+)\s*[<(]',
      r'(?:const|let|var)\s+(\w+)\s*[:=]',
      r'class\s+(\w+)\s*[{<]',
      r'interface\s+(\w+)\s*[{<]',
      r'type\s+(\w+)\s*=',
      r'enum\s+(\w+)\s*{',
    ],
    'dart': [
      r'(?:void|Future|Stream|String|int|double|bool|dynamic|\w+)\s+(\w+)\s*\(',
      r'class\s+(\w+)\s*(?:extends|implements|with|{)',
      r'(?:final|var|late|const)\s+\w+\s+(\w+)\s*[=;]',
      r'mixin\s+(\w+)',
      r'enum\s+(\w+)\s*{',
    ],
    'java': [
      r'(?:public|private|protected|static|final|abstract|synchronized)\s+\w+\s+(\w+)\s*\(',
      r'class\s+(\w+)\s*(?:extends|implements|{)',
      r'interface\s+(\w+)\s*[{<]',
      r'enum\s+(\w+)\s*{',
    ],
    'kotlin': [
      r'fun\s+(\w+)\s*[<(]',
      r'class\s+(\w+)\s*[(<{]',
      r'data class\s+(\w+)',
      r'(?:val|var)\s+(\w+)\s*[:=]',
      r'object\s+(\w+)',
      r'interface\s+(\w+)',
      r'sealed class\s+(\w+)',
    ],
    'rust': [
      r'fn\s+(\w+)\s*[<(]',
      r'struct\s+(\w+)\s*[{<;]',
      r'enum\s+(\w+)\s*[{<]',
      r'trait\s+(\w+)\s*[{<]',
      r'impl\s+(?:\w+\s+for\s+)?(\w+)',
      r'(?:let|const|static)\s+(?:mut\s+)?(\w+)\s*[:=]',
      r'type\s+(\w+)\s*=',
      r'mod\s+(\w+)',
    ],
    'go': [
      r'func\s+(?:\(\w+ \*?\w+\)\s+)?(\w+)\s*\(',
      r'type\s+(\w+)\s+(?:struct|interface)',
      r'(?:var|const)\s+(\w+)\s+',
    ],
    'cpp': [
      r'(?:\w+\s+)?(\w+)\s*\([^;]*\)\s*(?:const)?\s*\{',
      r'class\s+(\w+)\s*[:{]',
      r'struct\s+(\w+)\s*[:{]',
      r'enum\s+(?:class\s+)?(\w+)',
      r'namespace\s+(\w+)',
      r'typedef\s+\w+\s+(\w+)\s*;',
      r'using\s+(\w+)\s*=',
    ],
  };

  // ── API publique ─────────────────────────────────────────────────────────

  /// Retourne la liste de mots-clés pour un langage donné.
  static List<String> forLanguage(String languageId) =>
      _data[languageId] ?? _data['plaintext'] ?? [];

  /// Extrait les symboles (noms de fonctions, classes, variables) d'un fichier.
  static List<String> extractSymbols(String content, String languageId) {
    final patterns = _symbolPatterns[languageId];
    if (patterns == null) return [];

    final symbols = <String>{};
    for (final pattern in patterns) {
      final re = RegExp(pattern, multiLine: true);
      for (final m in re.allMatches(content)) {
        final name = m.group(1);
        if (name != null && name.length > 1) {
          symbols.add(name);
        }
      }
    }
    return symbols.toList()..sort();
  }

  /// Retourne les suggestions filtrées par préfixe.
  /// Combine mots-clés du langage + symboles du fichier courant.
  static List<String> getSuggestions({
    required String prefix,
    required String languageId,
    String currentFileContent = '',
    List<String> workspaceSymbols = const [],
    int maxResults = 12,
  }) {
    if (prefix.isEmpty || prefix.length < 2) return [];

    final lower = prefix.toLowerCase();
    final keywords = forLanguage(languageId);
    final fileSymbols = extractSymbols(currentFileContent, languageId);

    final all = <String>{
      ...keywords,
      ...fileSymbols,
      ...workspaceSymbols,
    };

    final matches = all
        .where((k) => k.toLowerCase().startsWith(lower) && k != prefix)
        .toList()
      ..sort((a, b) {
        // Priorité : correspondance exacte de casse > begins with > rest
        final aExact = a.startsWith(prefix) ? 0 : 1;
        final bExact = b.startsWith(prefix) ? 0 : 1;
        if (aExact != bExact) return aExact - bExact;
        return a.length.compareTo(b.length);
      });

    return matches.take(maxResults).toList();
  }
}