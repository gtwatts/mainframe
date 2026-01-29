/**
 * MAINFRAME Bash Language Server
 *
 * Provides IntelliSense for MAINFRAME's 2,000+ bash functions.
 */

import * as fs from 'fs';
import * as path from 'path';
import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  CompletionItem,
  CompletionItemKind,
  TextDocumentPositionParams,
  TextDocumentSyncKind,
  InitializeResult,
  Hover,
  MarkupKind,
  SignatureHelp,
  SignatureInformation,
  ParameterInformation,
} from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';

// Create connection
const connection = createConnection(ProposedFeatures.all);

// Create document manager
const documents = new TextDocuments(TextDocument);

// Server state
let functionsPath: string | null = null;
let functionsData: any = null;
let completionItems: CompletionItem[] = [];

/**
 * Parse command line arguments
 */
function parseArgs(): void {
  const args = process.argv.slice(2);

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--functions-path' && i + 1 < args.length) {
      functionsPath = args[i + 1];
      i++;
    }
  }
}

/**
 * Load FUNCTIONS.json
 */
function loadFunctions(): boolean {
  if (!functionsPath || !fs.existsSync(functionsPath)) {
    connection.console.error(`FUNCTIONS.json not found at: ${functionsPath}`);
    return false;
  }

  try {
    const content = fs.readFileSync(functionsPath, 'utf-8');
    functionsData = JSON.parse(content);
    connection.console.log(`Loaded FUNCTIONS.json (version ${functionsData.version})`);
    return true;
  } catch (error) {
    connection.console.error(`Failed to load FUNCTIONS.json: ${error}`);
    return false;
  }
}

/**
 * Generate completion items from FUNCTIONS.json
 */
function generateCompletionItems(): void {
  if (!functionsData || !functionsData.libraries) {
    return;
  }

  completionItems = [];

  for (const [libName, lib] of Object.entries<any>(functionsData.libraries)) {
    if (!lib.functions) {
      continue;
    }

    for (const [funcName, func] of Object.entries<any>(lib.functions)) {
      const item: CompletionItem = {
        label: funcName,
        kind: CompletionItemKind.Function,
        detail: `${lib.file} - ${lib.description || libName}`,
        documentation: {
          kind: MarkupKind.Markdown,
          value: generateDocumentation(funcName, func, lib),
        },
        insertText: funcName + ' ',
        sortText: `0-${funcName}`,
        filterText: `${funcName} ${lib.description || ''}`.toLowerCase(),
        data: {
          library: libName,
          file: lib.file,
          category: lib.category || 'other',
          idempotent: func.idempotent || false,
          pure: func.pure || false,
        },
      };

      completionItems.push(item);
    }
  }

  connection.console.log(`Generated ${completionItems.length} completion items`);
}

/**
 * Generate markdown documentation for a function
 */
function generateDocumentation(funcName: string, func: any, lib: any): string {
  const parts: string[] = [];

  // Function signature
  if (func.signature) {
    parts.push('```bash');
    parts.push(func.signature);
    parts.push('```');
    parts.push('');
  }

  // Description
  parts.push(func.description || 'MAINFRAME function');
  parts.push('');

  // Library info
  parts.push(`**Library:** \`${lib.file}\``);

  if (lib.category) {
    parts.push(`**Category:** ${lib.category}`);
  }

  // Returns
  if (func.returns) {
    parts.push('');
    parts.push(`**Returns:** ${func.returns}`);
  }

  // Tags
  const tags: string[] = [];
  if (func.pure) {
    tags.push('pure');
  }
  if (func.idempotent) {
    tags.push('idempotent');
  }

  if (tags.length > 0) {
    parts.push('');
    parts.push(`**Tags:** ${tags.join(', ')}`);
  }

  // Examples
  if (func.examples && Array.isArray(func.examples) && func.examples.length > 0) {
    parts.push('');
    parts.push('**Examples:**');
    parts.push('');
    func.examples.forEach((example: string) => {
      parts.push('```bash');
      parts.push(example);
      parts.push('```');
    });
  }

  return parts.join('\n');
}

/**
 * Get function details for hover
 */
function getFunctionDetails(funcName: string): any | null {
  if (!functionsData || !functionsData.libraries) {
    return null;
  }

  for (const [libName, lib] of Object.entries<any>(functionsData.libraries)) {
    if (lib.functions && lib.functions[funcName]) {
      return {
        name: funcName,
        func: lib.functions[funcName],
        lib,
        libName,
      };
    }
  }

  return null;
}

/**
 * Parse function signature into parameters
 */
function parseSignature(signature: string): { params: string[]; description: string } {
  // Example: json_object "key=val" "key:type=val" ...
  const match = signature.match(/^(\w+)\s+(.+)$/);

  if (!match) {
    return { params: [], description: signature };
  }

  const funcName = match[1];
  const paramsStr = match[2];

  // Simple parameter extraction (quoted strings or words)
  const params: string[] = [];
  const regex = /"([^"]+)"|(\S+)/g;
  let m;

  while ((m = regex.exec(paramsStr)) !== null) {
    params.push(m[1] || m[2]);
  }

  return {
    params,
    description: signature,
  };
}

// Initialize server
connection.onInitialize((params: InitializeParams): InitializeResult => {
  connection.console.log('MAINFRAME LSP Server initializing...');

  // Parse args and load functions
  parseArgs();

  if (!loadFunctions()) {
    connection.console.error('Failed to load FUNCTIONS.json, server will have limited functionality');
  } else {
    generateCompletionItems();
  }

  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      completionProvider: {
        resolveProvider: false,
        triggerCharacters: ['_', '-'],
      },
      hoverProvider: true,
      signatureHelpProvider: {
        triggerCharacters: [' ', '('],
        retriggerCharacters: [','],
      },
    },
  };
});

connection.onInitialized(() => {
  connection.console.log('MAINFRAME LSP Server initialized');
});

// Completion handler
connection.onCompletion((params: TextDocumentPositionParams): CompletionItem[] => {
  const document = documents.get(params.textDocument.uri);
  if (!document) {
    return [];
  }

  const line = document.getText({
    start: { line: params.position.line, character: 0 },
    end: params.position,
  });

  // Only provide completions after whitespace or at start of line
  if (line.trim().length === 0 || /\s$/.test(line)) {
    return completionItems;
  }

  // Provide completions for partial matches
  const lastWord = line.match(/[a-zA-Z_][a-zA-Z0-9_-]*$/)?.[0];
  if (lastWord) {
    return completionItems.filter(item =>
      item.label.startsWith(lastWord)
    );
  }

  return [];
});

// Hover handler
connection.onHover((params: TextDocumentPositionParams): Hover | null => {
  const document = documents.get(params.textDocument.uri);
  if (!document) {
    return null;
  }

  // Get word at position
  const line = document.getText({
    start: { line: params.position.line, character: 0 },
    end: { line: params.position.line + 1, character: 0 },
  });

  const wordPattern = /[a-zA-Z_][a-zA-Z0-9_-]*/g;
  let match;
  let hoveredWord: string | null = null;

  while ((match = wordPattern.exec(line)) !== null) {
    const start = match.index;
    const end = start + match[0].length;

    if (start <= params.position.character && params.position.character <= end) {
      hoveredWord = match[0];
      break;
    }
  }

  if (!hoveredWord) {
    return null;
  }

  // Get function details
  const details = getFunctionDetails(hoveredWord);
  if (!details) {
    return null;
  }

  const doc = generateDocumentation(details.name, details.func, details.lib);

  return {
    contents: {
      kind: MarkupKind.Markdown,
      value: doc,
    },
  };
});

// Signature help handler
connection.onSignatureHelp((params: TextDocumentPositionParams): SignatureHelp | null => {
  const document = documents.get(params.textDocument.uri);
  if (!document) {
    return null;
  }

  // Get current line up to cursor
  const line = document.getText({
    start: { line: params.position.line, character: 0 },
    end: params.position,
  });

  // Find function name at start of command
  const funcMatch = line.match(/^\s*([a-zA-Z_][a-zA-Z0-9_-]*)/);
  if (!funcMatch) {
    return null;
  }

  const funcName = funcMatch[1];
  const details = getFunctionDetails(funcName);

  if (!details || !details.func.signature) {
    return null;
  }

  const { params: paramsList } = parseSignature(details.func.signature);

  // Count current parameter (by spaces after function name)
  const afterFunc = line.substring(funcMatch[0].length);
  const activeParameter = (afterFunc.match(/\s+/g) || []).length;

  const parameters: ParameterInformation[] = paramsList.map(p => ({
    label: p,
  }));

  const signatureInfo: SignatureInformation = {
    label: details.func.signature,
    documentation: {
      kind: MarkupKind.Markdown,
      value: details.func.description || '',
    },
    parameters,
  };

  return {
    signatures: [signatureInfo],
    activeSignature: 0,
    activeParameter: Math.min(activeParameter, parameters.length - 1),
  };
});

// Document management
documents.listen(connection);

// Start listening
connection.listen();
