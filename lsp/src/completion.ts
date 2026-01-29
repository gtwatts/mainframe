/**
 * Completion provider for MAINFRAME functions
 */

import { CompletionItem, CompletionItemKind, MarkupKind } from 'vscode-languageserver/node';
import { MetadataLoader } from './metadata';

export class CompletionProvider {
  constructor(private metadataLoader: MetadataLoader) {}

  /**
   * Get all completion items
   */
  getCompletions(): CompletionItem[] {
    const completions: CompletionItem[] = [];
    const functions = this.metadataLoader.getAllFunctions();

    for (const meta of functions) {
      completions.push({
        label: meta.name,
        kind: CompletionItemKind.Function,
        detail: meta.signature,
        documentation: {
          kind: MarkupKind.Markdown,
          value: this.formatDocumentation(meta.name, meta.description, meta.library),
        },
      });
    }

    return completions;
  }

  /**
   * Get completions filtered by prefix
   */
  getCompletionsByPrefix(prefix: string): CompletionItem[] {
    if (!prefix) {
      return this.getCompletions();
    }

    const completions: CompletionItem[] = [];
    const functions = this.metadataLoader.searchByPrefix(prefix);

    for (const meta of functions) {
      completions.push({
        label: meta.name,
        kind: CompletionItemKind.Function,
        detail: meta.signature,
        documentation: {
          kind: MarkupKind.Markdown,
          value: this.formatDocumentation(meta.name, meta.description, meta.library),
        },
      });
    }

    return completions;
  }

  /**
   * Format documentation in Markdown
   */
  private formatDocumentation(name: string, description: string, library: string): string {
    return `**${name}**\n\n${description}\n\n*Library: ${library}*`;
  }
}
