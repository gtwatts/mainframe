/**
 * Unit tests for HoverProvider
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { HoverProvider } from '../../hover';
import { MetadataLoader } from '../../metadata';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { Position } from 'vscode-languageserver-types';
import * as path from 'path';

describe('HoverProvider', () => {
  const testMetadataPath = path.join(__dirname, '../fixtures/test-metadata.json');
  let loader: MetadataLoader;
  let provider: HoverProvider;

  beforeEach(() => {
    loader = new MetadataLoader(testMetadataPath);
    loader.load();
    provider = new HoverProvider(loader);
  });

  describe('getHover', () => {
    it('returns hover for known function', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object "name=test"');
      const position = Position.create(0, 5); // Inside "json_object"

      const hover = provider.getHover(document, position);

      expect(hover).not.toBeNull();
      expect(hover?.contents).toBeDefined();
    });

    it('returns null for unknown function', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'unknown_func');
      const position = Position.create(0, 5);

      const hover = provider.getHover(document, position);

      expect(hover).toBeNull();
    });

    it('returns null when cursor not on a word', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, '   ');
      const position = Position.create(0, 1);

      const hover = provider.getHover(document, position);

      expect(hover).toBeNull();
    });

    it('includes function signature in code block', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'array_sort "b" "a"');
      const position = Position.create(0, 5);

      const hover = provider.getHover(document, position);
      const content = hover?.contents;
      const value = typeof content === 'object' && 'value' in content ? content.value : '';

      expect(value).toContain('```bash');
      expect(value).toContain('```');
    });

    it('includes library and category information', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object');
      const position = Position.create(0, 5);

      const hover = provider.getHover(document, position);
      const content = hover?.contents;
      const value = typeof content === 'object' && 'value' in content ? content.value : '';

      expect(value).toContain('Library:');
      expect(value).toContain('Category:');
    });

    it('formats content as Markdown', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'http_get');
      const position = Position.create(0, 5);

      const hover = provider.getHover(document, position);

      expect(hover?.contents).toHaveProperty('kind', 'markdown');
    });

    it('handles cursor at start of function name', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object');
      const position = Position.create(0, 0); // At 'j'

      const hover = provider.getHover(document, position);

      expect(hover).not.toBeNull();
      expect(hover?.contents).toBeDefined();
    });

    it('handles cursor at end of function name', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object');
      const position = Position.create(0, 10); // At 't' in "object"

      const hover = provider.getHover(document, position);

      expect(hover).not.toBeNull();
    });

    it('handles cursor just after function name', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object  ');
      const position = Position.create(0, 12); // After function, on second space

      const hover = provider.getHover(document, position);

      expect(hover).toBeNull(); // Space is not part of word
    });

    it('works with underscores in function names', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'validate_email');
      const position = Position.create(0, 9); // On underscore

      const hover = provider.getHover(document, position);

      expect(hover).not.toBeNull();
    });

    it('works across multiple lines', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        '#!/bin/bash\njson_object "name=test"\narray_sort'
      );
      const position = Position.create(1, 5); // Line 2, inside json_object

      const hover = provider.getHover(document, position);

      expect(hover).not.toBeNull();
    });

    it('distinguishes between different functions on same line', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'json_object | array_sort'
      );

      // Hover on json_object
      const hover1 = provider.getHover(document, Position.create(0, 5));
      expect(hover1).not.toBeNull();

      // Hover on array_sort
      const hover2 = provider.getHover(document, Position.create(0, 20));
      expect(hover2).not.toBeNull();

      // Should be different functions
      const content1 = hover1?.contents;
      const content2 = hover2?.contents;
      const value1 = typeof content1 === 'object' && 'value' in content1 ? content1.value : '';
      const value2 = typeof content2 === 'object' && 'value' in content2 ? content2.value : '';

      expect(value1).toContain('json_object');
      expect(value2).toContain('array_sort');
    });
  });

  describe('edge cases', () => {
    it('handles empty document', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, '');
      const position = Position.create(0, 0);

      const hover = provider.getHover(document, position);

      expect(hover).toBeNull();
    });

    it('handles document with only whitespace', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, '   \n   \n   ');
      const position = Position.create(1, 1);

      const hover = provider.getHover(document, position);

      expect(hover).toBeNull();
    });

    it('handles cursor beyond document end', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'test');
      const position = Position.create(10, 10); // Way beyond document

      const hover = provider.getHover(document, position);

      // Should not crash
      expect(hover === null || hover !== null).toBe(true);
    });

    it('handles special characters in document', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'echo "$json_object"');
      const position = Position.create(0, 10); // Inside json_object

      const hover = provider.getHover(document, position);

      expect(hover).not.toBeNull();
    });

    it('handles numbers in function names', () => {
      // Even though our test data doesn't have numbers, the code should handle them
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'func123_test');
      const position = Position.create(0, 5);

      const hover = provider.getHover(document, position);

      // Won't match, but shouldn't crash
      expect(hover).toBeNull();
    });
  });

  describe('performance', () => {
    it('returns hover quickly', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object');
      const position = Position.create(0, 5);

      const startTime = Date.now();
      provider.getHover(document, position);
      const endTime = Date.now();

      // Should complete in less than 50ms
      expect(endTime - startTime).toBeLessThan(50);
    });

    it('handles large documents efficiently', () => {
      const largeContent = Array(1000).fill('json_object\n').join('');
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, largeContent);
      const position = Position.create(500, 5);

      const startTime = Date.now();
      provider.getHover(document, position);
      const endTime = Date.now();

      // Should complete in less than 100ms even for large documents
      expect(endTime - startTime).toBeLessThan(100);
    });
  });
});
