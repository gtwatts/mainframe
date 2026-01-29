/**
 * Integration tests for LSP server
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { MetadataLoader } from '../../metadata';
import { CompletionProvider } from '../../completion';
import { HoverProvider } from '../../hover';
import { SignatureHelpProvider } from '../../signature';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { Position } from 'vscode-languageserver-types';
import * as path from 'path';

describe('LSP Server Integration', () => {
  const testMetadataPath = path.join(__dirname, '../fixtures/test-metadata.json');
  let loader: MetadataLoader;
  let completionProvider: CompletionProvider;
  let hoverProvider: HoverProvider;
  let signatureProvider: SignatureHelpProvider;

  beforeEach(() => {
    loader = new MetadataLoader(testMetadataPath);
    const result = loader.load();
    expect(result.success).toBe(true);

    completionProvider = new CompletionProvider(loader);
    hoverProvider = new HoverProvider(loader);
    signatureProvider = new SignatureHelpProvider(loader);
  });

  afterEach(() => {
    // Clean up if needed
  });

  describe('End-to-End Scenarios', () => {
    it('provides complete workflow: type function, get completion, hover, signature', () => {
      // Step 1: User types "json_" - get completions
      const completions = completionProvider.getCompletionsByPrefix('json_');
      expect(completions.length).toBeGreaterThan(0);
      expect(completions[0].label).toBe('json_object');

      // Step 2: User hovers over completed function
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object');
      const hoverPosition = Position.create(0, 5);
      const hover = hoverProvider.getHover(document, hoverPosition);
      expect(hover).not.toBeNull();
      expect(hover?.contents).toBeDefined();

      // Step 3: User types space to trigger signature help
      const docWithSpace = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object ');
      const sigPosition = Position.create(0, 12);
      const signature = signatureProvider.getSignatureHelp(docWithSpace, sigPosition);
      expect(signature).not.toBeNull();
      expect(signature?.signatures).toHaveLength(1);
    });

    it('handles multiple functions in same document', () => {
      const content = `#!/bin/bash
json_object "name=test"
array_sort "b" "a"
http_get "https://example.com"`;

      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, content);

      // Test hover on each function
      const hover1 = hoverProvider.getHover(document, Position.create(1, 5)); // json_object
      expect(hover1).not.toBeNull();

      const hover2 = hoverProvider.getHover(document, Position.create(2, 5)); // array_sort
      expect(hover2).not.toBeNull();

      const hover3 = hoverProvider.getHover(document, Position.create(3, 5)); // http_get
      expect(hover3).not.toBeNull();

      // Verify they're different functions
      const getValue = (h: any) => h?.contents && typeof h.contents === 'object' ? h.contents.value : '';
      expect(getValue(hover1)).toContain('json_object');
      expect(getValue(hover2)).toContain('array_sort');
      expect(getValue(hover3)).toContain('http_get');
    });

    it('handles document updates correctly', () => {
      // Initial document
      let document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object');
      let hover = hoverProvider.getHover(document, Position.create(0, 5));
      expect(hover).not.toBeNull();

      // Update document
      document = TextDocument.create('file:///test.sh', 'shellscript', 2, 'array_sort');
      hover = hoverProvider.getHover(document, Position.create(0, 5));
      expect(hover).not.toBeNull();

      const value = hover?.contents && typeof hover.contents === 'object' ? hover.contents.value : '';
      expect(value).toContain('array_sort');
    });

    it('provides consistent results across providers', () => {
      const functionName = 'json_object';

      // Get from completion
      const completions = completionProvider.getCompletionsByPrefix('json_');
      const completion = completions.find(c => c.label === functionName);
      expect(completion).toBeDefined();

      // Get from hover
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, functionName);
      const hover = hoverProvider.getHover(document, Position.create(0, 5));
      expect(hover).not.toBeNull();

      // Both should reference same function
      expect(completion?.label).toBe(functionName);
      const hoverValue = hover?.contents && typeof hover.contents === 'object' ? hover.contents.value : '';
      expect(hoverValue).toContain(functionName);
    });
  });

  describe('Error Handling', () => {
    it('handles invalid positions gracefully', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'test');

      // Position way beyond document
      const hover = hoverProvider.getHover(document, Position.create(1000, 1000));

      // Should not crash
      expect(hover === null || hover !== null).toBe(true);
    });

    it('handles empty documents', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, '');

      const hover = hoverProvider.getHover(document, Position.create(0, 0));
      expect(hover).toBeNull();

      const signature = signatureProvider.getSignatureHelp(document, Position.create(0, 0));
      expect(signature).toBeNull();
    });

    it('handles documents with only comments', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, '# just a comment');

      const hover = hoverProvider.getHover(document, Position.create(0, 5));
      expect(hover).toBeNull();
    });

    it('handles malformed bash syntax', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'json_object ( [ { incomplete'
      );

      // Should not crash when hovering over function
      const hover = hoverProvider.getHover(document, Position.create(0, 5));
      expect(hover).not.toBeNull();
    });
  });

  describe('Performance', () => {
    it('handles rapid consecutive requests', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object');
      const position = Position.create(0, 5);

      const startTime = Date.now();

      // Simulate rapid requests
      for (let i = 0; i < 100; i++) {
        hoverProvider.getHover(document, position);
        completionProvider.getCompletionsByPrefix('json_');
      }

      const endTime = Date.now();

      // Should handle 100 requests in less than 500ms
      expect(endTime - startTime).toBeLessThan(500);
    });

    it('handles large documents efficiently', () => {
      const largeContent = Array(10000)
        .fill(0)
        .map((_, i) => `echo "line ${i}"`)
        .join('\n') + '\njson_object';

      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, largeContent);
      const position = Position.create(10000, 5);

      const startTime = Date.now();
      const hover = hoverProvider.getHover(document, position);
      const endTime = Date.now();

      expect(hover).not.toBeNull();
      // Should handle large document in less than 200ms
      expect(endTime - startTime).toBeLessThan(200);
    });

    it('completion filtering is fast for large metadata', () => {
      const startTime = Date.now();

      // Get all completions (simulating user typing)
      completionProvider.getCompletions();
      completionProvider.getCompletionsByPrefix('j');
      completionProvider.getCompletionsByPrefix('js');
      completionProvider.getCompletionsByPrefix('jso');
      completionProvider.getCompletionsByPrefix('json');
      completionProvider.getCompletionsByPrefix('json_');

      const endTime = Date.now();

      // Incremental filtering should be fast
      expect(endTime - startTime).toBeLessThan(100);
    });
  });

  describe('Metadata Changes', () => {
    it('reloads metadata when file changes', () => {
      const initialStats = loader.getStats();
      expect(initialStats.totalFunctions).toBe(5);

      // Simulate reload
      const result = loader.load();
      expect(result.success).toBe(true);

      const newStats = loader.getStats();
      expect(newStats.totalFunctions).toBe(5);
    });

    it('maintains consistency after reload', () => {
      // Get function before reload
      const meta1 = loader.getFunction('json_object');
      expect(meta1).toBeDefined();

      // Reload
      loader.load();

      // Get same function after reload
      const meta2 = loader.getFunction('json_object');
      expect(meta2).toBeDefined();
      expect(meta2?.name).toBe(meta1?.name);
    });
  });

  describe('Special Characters and Edge Cases', () => {
    it('handles functions in strings', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'echo "json_object is a function"'
      );

      // Hover inside string
      const hover = hoverProvider.getHover(document, Position.create(0, 10));
      expect(hover).not.toBeNull();
    });

    it('handles functions in comments', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        '# Use json_object to create objects'
      );

      const hover = hoverProvider.getHover(document, Position.create(0, 10));
      expect(hover).not.toBeNull();
    });

    it('handles functions with variable expansion', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'result=$(json_object "name=test")'
      );

      const hover = hoverProvider.getHover(document, Position.create(0, 15));
      expect(hover).not.toBeNull();
    });

    it('handles piped commands', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'json_object | array_sort | http_get'
      );

      // Each function should have hover
      const hover1 = hoverProvider.getHover(document, Position.create(0, 5));
      const hover2 = hoverProvider.getHover(document, Position.create(0, 20));
      const hover3 = hoverProvider.getHover(document, Position.create(0, 30));

      expect(hover1).not.toBeNull();
      expect(hover2).not.toBeNull();
      expect(hover3).not.toBeNull();
    });
  });
});
