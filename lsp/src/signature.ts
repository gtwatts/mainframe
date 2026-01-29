/**
 * Signature help provider for MAINFRAME functions
 */

import { SignatureHelp, SignatureInformation, ParameterInformation } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { Position } from 'vscode-languageserver-types';
import { MetadataLoader } from './metadata';

export class SignatureHelpProvider {
  constructor(private metadataLoader: MetadataLoader) {}

  /**
   * Get signature help for a position in a document
   */
  getSignatureHelp(document: TextDocument, position: Position): SignatureHelp | null {
    const context = this.getFunctionCallContext(document, position);
    if (!context) {
      return null;
    }

    const meta = this.metadataLoader.getFunction(context.functionName);
    if (!meta) {
      return null;
    }

    const signature = SignatureInformation.create(
      meta.signature,
      meta.description
    );

    // Parse parameters from signature if available
    const params = this.extractParameters(meta.signature);
    if (params.length > 0) {
      signature.parameters = params.map(param =>
        ParameterInformation.create(param)
      );
    }

    return {
      signatures: [signature],
      activeSignature: 0,
      activeParameter: context.parameterIndex,
    };
  }

  /**
   * Get function call context at cursor position
   */
  private getFunctionCallContext(
    document: TextDocument,
    position: Position
  ): { functionName: string; parameterIndex: number } | null {
    const text = document.getText();
    const offset = document.offsetAt(position);

    // Find the start of the current command (go back to newline or start)
    let lineStart = offset;
    while (lineStart > 0 && text[lineStart - 1] !== '\n') {
      lineStart--;
    }

    const line = text.slice(lineStart, offset);

    // Extract function name (first word in the line)
    const match = line.match(/^\s*([a-zA-Z0-9_]+)/);
    if (!match) {
      return null;
    }

    const functionName = match[1];

    // Count parameters (simple heuristic: count spaces after function name)
    const afterFunction = line.slice(match[0].length);
    const parameterIndex = afterFunction.split(/\s+/).filter(s => s.length > 0).length;

    return { functionName, parameterIndex };
  }

  /**
   * Extract parameter names from signature
   */
  private extractParameters(signature: string): string[] {
    const params: string[] = [];

    // Match parameter patterns like "url", "[options]", "<required>"
    const matches = signature.matchAll(/[<\[]([a-zA-Z0-9_-]+)[\]>]/g);
    for (const match of matches) {
      params.push(match[1]);
    }

    return params;
  }
}
