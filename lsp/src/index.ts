/**
 * MAINFRAME Bash Language Server
 *
 * Provides comprehensive IntelliSense for MAINFRAME's 1,900+ bash functions:
 * - Smart autocompletion with snippets
 * - Rich hover documentation with examples
 * - Signature help as you type
 * - Document symbols (function usage outline)
 * - Go-to-definition support
 *
 * @module @mainframe/bash-lsp
 */

import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  InitializeResult,
  TextDocumentSyncKind,
  CompletionItem,
  CompletionItemKind,
  Hover,
  MarkupKind,
  SignatureHelp,
  SignatureInformation,
  ParameterInformation,
  DocumentSymbol,
  SymbolKind,
  Range,
  Position,
  InsertTextFormat,
  Location,
} from "vscode-languageserver/node";

import { TextDocument } from "vscode-languageserver-textdocument";
import * as fs from "fs";
import * as path from "path";

// ============================================================================
// Connection & Document Management
// ============================================================================

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

// ============================================================================
// Type Definitions
// ============================================================================

interface FunctionParameter {
  label: string;
  documentation: string;
  position: number;
  required: boolean;
  default: string | null;
}

interface FunctionSignature {
  function: string;
  signature: string;
  description: string;
  parameters: FunctionParameter[];
}

interface FunctionData {
  library: string;
  libraryFile: string;
  libraryDescription: string;
  category: string;
  signature: string;
  description: string;
  returns: string;
  params: FunctionParameter[];
  idempotent: boolean;
  pure: boolean;
  examples: string[];
  relatedFunctions: string[];
}

interface CompletionItemData extends CompletionItem {
  data: FunctionData;
}

interface LSPMetadata {
  version: string;
  generated: string;
  index_format: string;
  completions: CompletionItemData[];
  signatures: FunctionSignature[];
  libraries: Array<{
    name: string;
    file: string;
    description: string;
    category: string;
    functionCount: number;
  }>;
  categoryIndex: Array<{
    category: string;
    libraries: string[];
    functionCount: number;
  }>;
  stats: {
    total_completions: number;
    total_libraries: number;
    total_signatures: number;
    categories: string[];
  };
}

// ============================================================================
// Metadata Cache
// ============================================================================

let metadata: LSPMetadata | null = null;
const functionLookup = new Map<string, CompletionItemData>();
const signatureLookup = new Map<string, FunctionSignature>();

/**
 * Load FUNCTIONS.lsp.json metadata from MAINFRAME_ROOT
 */
function loadMetadata(): void {
  const mainframeRoot =
    process.env.MAINFRAME_ROOT ||
    path.join(process.env.HOME || "", ".mainframe");
  const metadataPath = path.join(mainframeRoot, "FUNCTIONS.lsp.json");

  try {
    if (fs.existsSync(metadataPath)) {
      const data = fs.readFileSync(metadataPath, "utf-8");
      metadata = JSON.parse(data) as LSPMetadata;

      // Build function lookup map
      functionLookup.clear();
      for (const item of metadata.completions) {
        functionLookup.set(item.label, item);
      }

      // Build signature lookup map
      signatureLookup.clear();
      for (const sig of metadata.signatures) {
        signatureLookup.set(sig.function, sig);
      }

      connection.console.log(
        `✓ Loaded ${metadata.stats.total_completions} functions from ${metadata.stats.total_libraries} libraries`,
      );
      connection.console.log(
        `✓ Loaded ${metadata.stats.total_signatures} signature help entries`,
      );
    } else {
      connection.console.warn(
        `FUNCTIONS.lsp.json not found at ${metadataPath}`,
      );
      connection.console.warn("Run: ./lsp/scripts/generate-lsp-metadata.sh");
    }
  } catch (error) {
    connection.console.error(`Failed to load metadata: ${error}`);
  }
}

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Get word at position in document
 */
function getWordAtPosition(document: TextDocument, position: Position): string {
  const text = document.getText();
  const offset = document.offsetAt(position);

  let start = offset;
  let end = offset;

  // Find word boundaries (alphanumeric + underscore)
  while (start > 0 && /[a-zA-Z0-9_]/.test(text[start - 1])) {
    start--;
  }
  while (end < text.length && /[a-zA-Z0-9_]/.test(text[end])) {
    end++;
  }

  return text.slice(start, end);
}

/**
 * Find all function calls in document
 */
function findFunctionCalls(
  document: TextDocument,
): Array<{ name: string; range: Range }> {
  const text = document.getText();
  const calls: Array<{ name: string; range: Range }> = [];

  // Match function calls: function_name (optionally followed by spaces and args)
  // This regex matches bash function calls
  const functionCallRegex = /\b([a-z_][a-z0-9_]*)\s*(?:\(|$|\s)/gi;

  let match: RegExpExecArray | null;
  while ((match = functionCallRegex.exec(text)) !== null) {
    const funcName = match[1];

    // Check if this is a MAINFRAME function
    if (functionLookup.has(funcName)) {
      const startPos = document.positionAt(match.index);
      const endPos = document.positionAt(match.index + funcName.length);

      calls.push({
        name: funcName,
        range: Range.create(startPos, endPos),
      });
    }
  }

  return calls;
}

/**
 * Get current function call context (for signature help)
 */
function getCurrentFunctionCall(
  document: TextDocument,
  position: Position,
): string | null {
  const text = document.getText();
  const offset = document.offsetAt(position);

  // Search backwards for function name (simple heuristic)
  const searchStart = Math.max(0, offset - 200);
  const searchText = text.slice(searchStart, offset);

  // Find last function-like word before cursor
  const matches = searchText.match(/\b([a-z_][a-z0-9_]*)\s+[^;\n]*$/i);
  if (matches && matches[1]) {
    return matches[1];
  }

  return null;
}

/**
 * Build rich markdown documentation for hover
 */
function buildHoverMarkdown(item: CompletionItemData): string {
  const data = item.data;
  const parts: string[] = [];

  // Function name and signature
  parts.push(`# ${item.label}`);
  parts.push("");
  parts.push("```bash");
  parts.push(data.signature);
  parts.push("```");
  parts.push("");

  // Description
  if (data.description) {
    parts.push(data.description);
    parts.push("");
  }

  // Parameters
  if (data.params && data.params.length > 0) {
    parts.push("## Parameters");
    parts.push("");
    for (const param of data.params) {
      const required = param.required ? "**required**" : "*optional*";
      const defaultVal = param.default
        ? ` (default: \`${param.default}\`)`
        : "";
      parts.push(`- **${param.label}** ${required}${defaultVal}`);
      if (param.documentation) {
        parts.push(`  ${param.documentation}`);
      }
    }
    parts.push("");
  }

  // Returns
  if (data.returns) {
    parts.push(`**Returns:** \`${data.returns}\``);
    parts.push("");
  }

  // Examples
  if (data.examples && data.examples.length > 0) {
    parts.push("## Examples");
    parts.push("");
    for (const example of data.examples) {
      parts.push("```bash");
      parts.push(example);
      parts.push("```");
      parts.push("");
    }
  }

  // Related functions
  if (data.relatedFunctions && data.relatedFunctions.length > 0) {
    parts.push(`**Related:** ${data.relatedFunctions.join(", ")}`);
    parts.push("");
  }

  // Metadata
  const tags: string[] = [];
  if (data.pure) tags.push("pure");
  if (data.idempotent) tags.push("idempotent");
  if (tags.length > 0) {
    parts.push(`*${tags.join(" · ")}*`);
    parts.push("");
  }

  parts.push("---");
  parts.push(`*Library: ${data.library} · Category: ${data.category}*`);

  return parts.join("\n");
}

// ============================================================================
// LSP Handlers
// ============================================================================

/**
 * Initialize LSP server
 */
connection.onInitialize((params: InitializeParams): InitializeResult => {
  loadMetadata();

  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,

      // Completion with snippets
      completionProvider: {
        resolveProvider: false,
        triggerCharacters: ["_", "$"],
      },

      // Hover documentation
      hoverProvider: true,

      // Signature help as you type
      signatureHelpProvider: {
        triggerCharacters: [" ", '"', "'"],
        retriggerCharacters: [" "],
      },

      // Document symbols (outline)
      documentSymbolProvider: true,

      // Go-to-definition
      definitionProvider: true,
    },
  };
});

/**
 * Completion Provider - Smart autocompletion
 */
connection.onCompletion((params): CompletionItem[] => {
  if (!metadata) return [];

  const document = documents.get(params.textDocument.uri);
  if (!document) return [];

  // Get current word being typed
  const currentWord = getWordAtPosition(document, params.position);

  // Return all completions (VSCode will filter based on user input)
  return metadata.completions.map((item) => {
    const data = item.data;

    // Build snippet with parameter placeholders if function has params
    let insertText = item.label;
    let insertTextFormat: 1 | 2 = InsertTextFormat.PlainText;

    if (data.params && data.params.length > 0) {
      const placeholders = data.params
        .map((p, idx) => `\${${idx + 1}:${p.label}}`)
        .join(" ");
      insertText = `${item.label} ${placeholders}`;
      insertTextFormat = InsertTextFormat.Snippet;
    }

    return {
      label: item.label,
      kind: CompletionItemKind.Function,
      detail: data.signature,
      documentation: {
        kind: MarkupKind.Markdown,
        value: `${data.description}\n\n*${data.category} · ${data.library}*`,
      },
      insertText,
      insertTextFormat,
      sortText: item.sortText,
      filterText: item.filterText,
      data: item.data,
    };
  });
});

/**
 * Hover Provider - Rich documentation on hover
 */
connection.onHover((params): Hover | null => {
  const document = documents.get(params.textDocument.uri);
  if (!document) return null;

  const word = getWordAtPosition(document, params.position);
  const item = functionLookup.get(word);

  if (!item) return null;

  return {
    contents: {
      kind: MarkupKind.Markdown,
      value: buildHoverMarkdown(item),
    },
  };
});

/**
 * Signature Help Provider - Parameter info as you type
 */
connection.onSignatureHelp((params): SignatureHelp | null => {
  const document = documents.get(params.textDocument.uri);
  if (!document) return null;

  // Find current function call
  const funcName = getCurrentFunctionCall(document, params.position);
  if (!funcName) return null;

  const signature = signatureLookup.get(funcName);
  if (!signature) return null;

  // Build parameter information
  const parameters: ParameterInformation[] = signature.parameters.map(
    (param) => {
      const required = param.required ? " (required)" : " (optional)";
      const defaultVal = param.default ? ` = ${param.default}` : "";

      return {
        label: param.label,
        documentation: {
          kind: MarkupKind.Markdown,
          value: `${param.documentation}${required}${defaultVal}`,
        },
      };
    },
  );

  // Build signature information
  const sigInfo: SignatureInformation = {
    label: signature.signature,
    documentation: {
      kind: MarkupKind.Markdown,
      value: signature.description,
    },
    parameters,
  };

  // Determine active parameter (simple heuristic: count spaces)
  const text = document.getText();
  const offset = document.offsetAt(params.position);
  const lineStart = document.offsetAt({
    line: params.position.line,
    character: 0,
  });
  const lineText = text.slice(lineStart, offset);

  // Count arguments by counting spaces after function name
  const afterFunc = lineText.slice(
    lineText.indexOf(funcName) + funcName.length,
  );
  const spaceCount = (afterFunc.match(/\s+\S+/g) || []).length;

  return {
    signatures: [sigInfo],
    activeSignature: 0,
    activeParameter: Math.min(spaceCount, parameters.length - 1),
  };
});

/**
 * Document Symbols Provider - Function call outline
 */
connection.onDocumentSymbol((params): DocumentSymbol[] => {
  const document = documents.get(params.textDocument.uri);
  if (!document) return [];

  const calls = findFunctionCalls(document);
  const symbols: DocumentSymbol[] = [];

  for (const call of calls) {
    const item = functionLookup.get(call.name);
    if (!item) continue;

    const symbol: DocumentSymbol = {
      name: call.name,
      detail: item.data.signature,
      kind: SymbolKind.Function,
      range: call.range,
      selectionRange: call.range,
    };

    symbols.push(symbol);
  }

  return symbols;
});

/**
 * Go-to-Definition Provider - Jump to library file
 */
connection.onDefinition((params): Location | null => {
  const document = documents.get(params.textDocument.uri);
  if (!document) return null;

  const word = getWordAtPosition(document, params.position);
  const item = functionLookup.get(word);

  if (!item) return null;

  // Build path to library file
  const mainframeRoot =
    process.env.MAINFRAME_ROOT ||
    path.join(process.env.HOME || "", ".mainframe");
  const libraryPath = path.join(mainframeRoot, item.data.libraryFile);

  // Return location of library file (top of file for now)
  // TODO: Could parse library file to find exact function definition line
  return {
    uri: `file://${libraryPath}`,
    range: Range.create(0, 0, 0, 0),
  };
});

// ============================================================================
// Server Lifecycle
// ============================================================================

documents.listen(connection);
connection.listen();

connection.console.log("MAINFRAME Bash LSP server started");
