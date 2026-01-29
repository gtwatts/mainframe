/**
 * Hover provider for MAINFRAME functions
 */

import { Hover, MarkupKind } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { Position } from 'vscode-languageserver-types';
import { MetadataLoader } from './metadata';

export class HoverProvider {
  constructor(private metadataLoader: MetadataLoader) {}

  /**
   * Get hover information for a position in a document
   */
  getHover(document: TextDocument, position: Position): Hover | null {
    const word = this.getWordAtPosition(document, position);
    if (!word) {
      return null;
    }

    const meta = this.metadataLoader.getFunction(word);
    if (!meta) {
      return null;
    }

    return {
      contents: {
        kind: MarkupKind.Markdown,
        value: this.formatHoverContent(meta.name, meta.signature, meta.description, meta.library, meta.category),
      },
    };
  }

  /**
   * Extract word at cursor position
   */
  private getWordAtPosition(document: TextDocument, position: Position): string | null {
    const text = document.getText();
    const offset = document.offsetAt(position);

    // Find word boundaries (bash function names: [a-zA-Z0-9_])
    let start = offset;
    let end = offset;

    while (start > 0 && /[a-zA-Z0-9_]/.test(text[start - 1])) {
      start--;
    }

    while (end < text.length && /[a-zA-Z0-9_]/.test(text[end])) {
      end++;
    }

    if (start === end) {
      return null;
    }

    return text.slice(start, end);
  }

  /**
   * Format hover content in Markdown
   */
  private formatHoverContent(
    name: string,
    signature: string,
    description: string,
    library: string,
    category: string
  ): string {
    return `**${name}**\n\n\`\`\`bash\n${signature}\n\`\`\`\n\n${description}\n\n*Library: ${library} | Category: ${category}*`;
  }
}
