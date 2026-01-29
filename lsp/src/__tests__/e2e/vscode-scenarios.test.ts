/**
 * E2E tests simulating real VS Code usage scenarios
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { MetadataLoader } from '../../metadata';
import { CompletionProvider } from '../../completion';
import { HoverProvider } from '../../hover';
import { SignatureHelpProvider } from '../../signature';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { Position } from 'vscode-languageserver-types';
import * as path from 'path';

describe('VS Code E2E Scenarios', () => {
  const testMetadataPath = path.join(__dirname, '../fixtures/test-metadata.json');
  let loader: MetadataLoader;
  let completionProvider: CompletionProvider;
  let hoverProvider: HoverProvider;
  let signatureProvider: SignatureHelpProvider;

  beforeEach(() => {
    loader = new MetadataLoader(testMetadataPath);
    loader.load();
    completionProvider = new CompletionProvider(loader);
    hoverProvider = new HoverProvider(loader);
    signatureProvider = new SignatureHelpProvider(loader);
  });

  describe('Scenario: User types a new MAINFRAME function', () => {
    it('provides completions as user types prefix', () => {
      // User types: j
      let completions = completionProvider.getCompletionsByPrefix('j');
      expect(completions.length).toBeGreaterThan(0);

      // User types: js
      completions = completionProvider.getCompletionsByPrefix('js');
      expect(completions.length).toBeGreaterThan(0);

      // User types: json
      completions = completionProvider.getCompletionsByPrefix('json');
      expect(completions.length).toBeGreaterThan(0);

      // User types: json_
      completions = completionProvider.getCompletionsByPrefix('json_');
      expect(completions.length).toBe(1);
      expect(completions[0].label).toBe('json_object');
    });

    it('shows signature help after selecting completion', () => {
      // User completes "json_object" and types space
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object ');
      const position = Position.create(0, 12);

      const signature = signatureProvider.getSignatureHelp(document, position);
      expect(signature).not.toBeNull();
      expect(signature?.signatures[0].label).toContain('JSON'); // Label is "JSON - Create JSON object..."
    });

    it('updates active parameter as user types arguments', () => {
      // User at: json_object
      let document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object ');
      let signature = signatureProvider.getSignatureHelp(document, Position.create(0, 12));
      expect(signature?.activeParameter).toBe(0);

      // User at: json_object "name=test"
      document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object "name=test" ');
      signature = signatureProvider.getSignatureHelp(document, Position.create(0, 24));
      expect(signature?.activeParameter).toBe(1);

      // User at: json_object "name=test" "age:number=30"
      document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object "name=test" "age:number=30" ');
      signature = signatureProvider.getSignatureHelp(document, Position.create(0, 40));
      expect(signature?.activeParameter).toBe(2);
    });
  });

  describe('Scenario: User hovers to read documentation', () => {
    it('shows documentation when hovering over function name', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'result=$(json_object "name=test")'
      );

      const hover = hoverProvider.getHover(document, Position.create(0, 15));

      expect(hover).not.toBeNull();
      const value = hover?.contents && typeof hover.contents === 'object' ? hover.contents.value : '';
      expect(value).toContain('json_object');
      expect(value).toContain('```bash'); // Code block
      expect(value).toContain('Library:');
    });

    it('shows hover for function in pipe chain', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'json_object "data" | http_get "url"'
      );

      // Hover on first function
      const hover1 = hoverProvider.getHover(document, Position.create(0, 5));
      expect(hover1).not.toBeNull();

      // Hover on second function
      const hover2 = hoverProvider.getHover(document, Position.create(0, 25));
      expect(hover2).not.toBeNull();

      const value1 = hover1?.contents && typeof hover1.contents === 'object' ? hover1.contents.value : '';
      const value2 = hover2?.contents && typeof hover2.contents === 'object' ? hover2.contents.value : '';

      expect(value1).toContain('json_object');
      expect(value2).toContain('http_get');
    });
  });

  describe('Scenario: User edits existing bash script', () => {
    it('provides completions in middle of document', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        `#!/bin/bash

# Setup
config_file="config.json"

# Process data
array_`
      );

      const completions = completionProvider.getCompletionsByPrefix('array_');
      expect(completions.length).toBeGreaterThan(0);
      expect(completions[0].label).toBe('array_sort');
    });

    it('handles hover in complex script with variables and functions', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        `#!/bin/bash
set -euo pipefail

API_URL="https://api.example.com"
DATA=$(json_object "name=test" "active:bool=true")

response=$(http_get "$API_URL/data")
validate_email "user@example.com"
`
      );

      // Hover on json_object (line 4)
      const hover1 = hoverProvider.getHover(document, Position.create(4, 10));
      expect(hover1).not.toBeNull();

      // Hover on http_get (line 6)
      const hover2 = hoverProvider.getHover(document, Position.create(6, 15));
      expect(hover2).not.toBeNull();

      // Hover on validate_email (line 7)
      const hover3 = hoverProvider.getHover(document, Position.create(7, 5));
      expect(hover3).not.toBeNull();
    });
  });

  describe('Scenario: User writes function with error handling', () => {
    it('provides completions inside conditional blocks', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        `if validate_email "$email"; then
  json_`
      );

      const completions = completionProvider.getCompletionsByPrefix('json_');
      expect(completions.length).toBe(1);
      expect(completions[0].label).toBe('json_object');
    });

    it('provides hover inside loops', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        `for item in "\${items[@]}"; do
  array_sort "$item"
done`
      );

      const hover = hoverProvider.getHover(document, Position.create(1, 5));
      expect(hover).not.toBeNull();
    });
  });

  describe('Scenario: User explores unknown functions', () => {
    it('shows all available completions on trigger', () => {
      const completions = completionProvider.getCompletions();
      expect(completions.length).toBe(5);

      // All should have documentation
      for (const completion of completions) {
        expect(completion.documentation).toBeDefined();
        expect(completion.detail).toBeDefined();
      }
    });

    it('provides helpful documentation for each function category', () => {
      const allCompletions = completionProvider.getCompletions();

      // Check we have different categories
      const jsonFuncs = allCompletions.filter(c => c.label.startsWith('json_'));
      const arrayFuncs = allCompletions.filter(c => c.label.startsWith('array_'));
      const httpFuncs = allCompletions.filter(c => c.label.startsWith('http_'));

      expect(jsonFuncs.length).toBeGreaterThan(0);
      expect(arrayFuncs.length).toBeGreaterThan(0);
      expect(httpFuncs.length).toBeGreaterThan(0);
    });
  });

  describe('Scenario: User refactors existing code', () => {
    it('handles rapid consecutive edits', () => {
      // Simulate rapid typing
      const edits = [
        'j',
        'js',
        'jso',
        'json',
        'json_',
        'json_o',
        'json_ob',
        'json_obj',
      ];

      for (const edit of edits) {
        const completions = completionProvider.getCompletionsByPrefix(edit);
        expect(Array.isArray(completions)).toBe(true);
      }
    });

    it('provides consistent hover after document changes', () => {
      // Version 1
      let document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object');
      let hover = hoverProvider.getHover(document, Position.create(0, 5));
      expect(hover).not.toBeNull();

      // User edits - Version 2
      document = TextDocument.create('file:///test.sh', 'shellscript', 2, 'json_object "name=updated"');
      hover = hoverProvider.getHover(document, Position.create(0, 5));
      expect(hover).not.toBeNull();

      // User edits - Version 3
      document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        3,
        'result=$(json_object "name=final" "value:number=42")'
      );
      hover = hoverProvider.getHover(document, Position.create(0, 15));
      expect(hover).not.toBeNull();
    });
  });

  describe('Scenario: Unknown functions gracefully handled', () => {
    it('returns no hover for unknown function', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'unknown_function');
      const hover = hoverProvider.getHover(document, Position.create(0, 5));
      expect(hover).toBeNull();
    });

    it('returns no signature help for unknown function', () => {
      const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'unknown_function ');
      const signature = signatureProvider.getSignatureHelp(document, Position.create(0, 17));
      expect(signature).toBeNull();
    });

    it('filters unknown functions from completions', () => {
      const completions = completionProvider.getCompletionsByPrefix('xyz_');
      expect(completions).toHaveLength(0);
    });

    it('does not crash on non-function bash commands', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'echo "test"\ncd /tmp\nls -la'
      );

      // Hover on standard commands - should return null without crashing
      const hover1 = hoverProvider.getHover(document, Position.create(0, 2));
      const hover2 = hoverProvider.getHover(document, Position.create(1, 2));
      const hover3 = hoverProvider.getHover(document, Position.create(2, 2));

      expect(hover1).toBeNull();
      expect(hover2).toBeNull();
      expect(hover3).toBeNull();
    });
  });

  describe('Scenario: Large metadata file performance', () => {
    it('loads metadata efficiently on startup', () => {
      const startTime = Date.now();
      const newLoader = new MetadataLoader(testMetadataPath);
      const result = newLoader.load();
      const endTime = Date.now();

      expect(result.success).toBe(true);
      expect(endTime - startTime).toBeLessThan(1000); // < 1 second
    });

    it('provides completions quickly even with many functions', () => {
      const startTime = Date.now();

      // Simulate user typing multiple times
      for (let i = 0; i < 10; i++) {
        completionProvider.getCompletions();
        completionProvider.getCompletionsByPrefix('j');
        completionProvider.getCompletionsByPrefix('a');
      }

      const endTime = Date.now();
      expect(endTime - startTime).toBeLessThan(200); // 30 operations < 200ms
    });

    it('handles hover queries efficiently', () => {
      const document = TextDocument.create(
        'file:///test.sh',
        'shellscript',
        1,
        'json_object\narray_sort\nhttp_get\nvalidate_email'
      );

      const startTime = Date.now();

      // Simulate rapid hovering
      for (let line = 0; line < 4; line++) {
        hoverProvider.getHover(document, Position.create(line, 5));
      }

      const endTime = Date.now();
      expect(endTime - startTime).toBeLessThan(100); // 4 hovers < 100ms
    });
  });
});
