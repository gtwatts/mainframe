/**
 * Type definitions for MAINFRAME LSP metadata
 */

export interface FunctionParameter {
  label: string;
  documentation: string;
  position: number;
  required: boolean;
  default: string | null;
}

export interface FunctionSignature {
  function: string;
  signature: string;
  description: string;
  parameters: FunctionParameter[];
}

export interface FunctionData {
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

export interface CompletionItemData {
  label: string;
  kind: string;
  detail: string;
  documentation: string;
  insertText: string;
  insertTextFormat: number;
  sortText: string;
  filterText: string;
  tags: string[];
  data: FunctionData;
}

export interface LibraryInfo {
  name: string;
  file: string;
  description: string;
  category: string;
  functionCount: number;
}

export interface CategoryIndex {
  category: string;
  libraries: string[];
  functionCount: number;
}

export interface LSPStats {
  total_completions: number;
  total_libraries: number;
  total_signatures: number;
  categories: string[];
}

export interface LSPMetadata {
  version: string;
  generated: string;
  index_format: string;
  completions: CompletionItemData[];
  signatures: FunctionSignature[];
  libraries: LibraryInfo[];
  categoryIndex: CategoryIndex[];
  stats: LSPStats;
}
