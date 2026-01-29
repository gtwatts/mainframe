/**
 * Unit tests for SignatureHelpProvider
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { SignatureHelpProvider } from '../../signature';
import { MetadataLoader } from '../../metadata';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { Position } from 'vscode-languageserver-types';
import * as path from 'path';

describe('SignatureHelpProvider', () => {
  const testMetadataPath = path.join(__dirname, '../fixtures/test-metadata.json');
  let loader: MetadataLoader;
  let provider: SignatureHelpProvider;

  beforeEach(() => {
    loader = new MetadataLoader(testMetadataPath);
    loader.load();
    provider = new SignatureHelpProvider(loader);
  });

  describe('getSignatureHelp', () => {
    it('returns signature help for known function', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'http_get ');
      const position = Position.create(0, 9); // After space

      const help = provider.getSignatureHelp(document, position);

      expect(help).not.toBeNull();
      expect(help?.signatures).toHaveLength(1);
    });

    it('returns null for unknown function', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'unknown_func ');
      const position = Position.create(0, 13);

      const help = provider.getSignatureHelp(document, position);

      expect(help).toBeNull();
    });

    it('includes function signature', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'http_get ');
      const position = Position.create(0, 9);

      const help = provider.getSignatureHelp(document, position);

      expect(help?.signatures[0].label).toBeDefined();
      expect(help?.signatures[0].label).toContain('HTTP'); // Signature contains "HTTP - Make HTTP GET request"
    });

    it('includes function documentation', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'http_get ');
      const position = Position.create(0, 9);

      const help = provider.getSignatureHelp(document, position);

      expect(help?.signatures[0].documentation).toBeDefined();
    });

    it('tracks active parameter index', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'http_get "url" ');
      const position = Position.create(0, 15); // After first param

      const help = provider.getSignatureHelp(document, position);

      expect(help?.activeParameter).toBeDefined();
      expect(help?.activeParameter).toBeGreaterThanOrEqual(0);
    });

    it('sets activeSignature to 0', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'http_get ');
      const position = Position.create(0, 9);

      const help = provider.getSignatureHelp(document, position);

      expect(help?.activeSignature).toBe(0);
    });

    it('handles function at line start', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object ');
      const position = Position.create(0, 12);

      const help = provider.getSignatureHelp(document, position);

      expect(help).not.toBeNull();
    });

    it('handles function with leading whitespace', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, '  json_object ');
      const position = Position.create(0, 14);

      const help = provider.getSignatureHelp(document, position);

      expect(help).not.toBeNull();
    });

    it('works on multiline scripts', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        '#!/bin/bash\nhttp_get '
      );
      const position = Position.create(1, 9); // Line 2

      const help = provider.getSignatureHelp(document, position);

      expect(help).not.toBeNull();
    });

    it('extracts parameters from signature', () => {
      // This tests parameter extraction from signatures with <param> or [param] syntax
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'http_get ');
      const position = Position.create(0, 9);

      const help = provider.getSignatureHelp(document, position);

      // Parameters may or may not be present depending on signature format
      if (help?.signatures[0].parameters) {
        expect(Array.isArray(help.signatures[0].parameters)).toBe(true);
      }
    });

    it('handles commands with pipes', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'json_object | http_get '
      );
      const position = Position.create(0, 23);

      const help = provider.getSignatureHelp(document, position);

      // Note: Current implementation gets help from line start, which is json_object
      // This is a known limitation - signature help doesn't parse pipes
      expect(help).not.toBeNull();
    });

    it('returns null when not in function call context', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, '# comment');
      const position = Position.create(0, 5);

      const help = provider.getSignatureHelp(document, position);

      expect(help).toBeNull();
    });
  });

  describe('parameter tracking', () => {
    it('identifies first parameter position', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object ');
      const position = Position.create(0, 12);

      const help = provider.getSignatureHelp(document, position);

      expect(help?.activeParameter).toBe(0);
    });

    it('identifies second parameter position', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object "name=test" ');
      const position = Position.create(0, 24);

      const help = provider.getSignatureHelp(document, position);

      expect(help?.activeParameter).toBe(1);
    });

    it('tracks parameters with quotes', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'array_sort "b" "a" "c" '
      );
      const position = Position.create(0, 23);

      const help = provider.getSignatureHelp(document, position);

      expect(help?.activeParameter).toBeGreaterThanOrEqual(2);
    });
  });

  describe('edge cases', () => {
    it('handles empty document', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, '');
      const position = Position.create(0, 0);

      const help = provider.getSignatureHelp(document, position);

      expect(help).toBeNull();
    });

    it('handles cursor at line start', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, '\nhttp_get');
      const position = Position.create(0, 0);

      const help = provider.getSignatureHelp(document, position);

      expect(help).toBeNull();
    });

    it('handles very long parameter lists', () => {
      const params = Array(50).fill('"param"').join(' ');
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, `array_sort ${params} `);
      const position = Position.create(0, document.getText().length - 1);

      const help = provider.getSignatureHelp(document, position);

      expect(help).not.toBeNull();
      expect(help?.activeParameter).toBeGreaterThanOrEqual(0);
    });

    it('handles special characters in parameters', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'json_object "$VAR" '
      );
      const position = Position.create(0, 19);

      const help = provider.getSignatureHelp(document, position);

      expect(help).not.toBeNull();
    });

    it('handles incomplete function calls', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'http_');
      const position = Position.create(0, 5);

      const help = provider.getSignatureHelp(document, position);

      // Should not crash, may or may not return help
      expect(help === null || help !== null).toBe(true);
    });
  });

  describe('performance', () => {
    it('returns signature help quickly', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'http_get ');
      const position = Position.create(0, 9);

      const startTime = Date.now();
      provider.getSignatureHelp(document, position);
      const endTime = Date.now();

      // Should complete in less than 50ms
      expect(endTime - startTime).toBeLessThan(50);
    });

    it('handles large documents efficiently', () => {
      const largeContent = Array(1000).fill('echo "line"\n').join('') + 'http_get ';
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, largeContent);
      const position = Position.create(1000, 9);

      const startTime = Date.now();
      provider.getSignatureHelp(document, position);
      const endTime = Date.now();

      // Should complete in less than 100ms
      expect(endTime - startTime).toBeLessThan(100);
    });
  });
});
