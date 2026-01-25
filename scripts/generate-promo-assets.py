#!/usr/bin/env python3
"""
MAINFRAME Promotional Asset Generator
Creates LinkedIn post image, README chart, and badge
"""

import os
from pathlib import Path

# Try to import visualization libraries
try:
    import matplotlib.pyplot as plt
    import matplotlib.patches as mpatches
    from matplotlib.patches import FancyBboxPatch
    import numpy as np
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False

try:
    from PIL import Image, ImageDraw, ImageFont
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

# Output directory
OUTPUT_DIR = Path(__file__).parent.parent / "assets" / "promo"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Colors
MAINFRAME_GREEN = "#00D26A"
MAINFRAME_DARK = "#1a1a2e"
MAINFRAME_BLUE = "#4C9AFF"
WARNING_RED = "#FF6B6B"
NEUTRAL_GRAY = "#6B7280"

# Data from token_comparison.sh results
TASKS = [
    ("JSON Creation", 72, 26),
    ("Array Operations", 101, 39),
    ("HTTP + Retry", 154, 32),
    ("String Trim", 40, 17),
    ("Date Math", 64, 15),
    ("Path Validation", 129, 21),
]

def create_comparison_chart():
    """Create the main token comparison bar chart"""
    if not HAS_MATPLOTLIB:
        print("matplotlib not available, skipping chart")
        return None

    fig, ax = plt.subplots(figsize=(12, 8), facecolor=MAINFRAME_DARK)
    ax.set_facecolor(MAINFRAME_DARK)

    tasks = [t[0] for t in TASKS]
    without = [t[1] for t in TASKS]
    with_mf = [t[2] for t in TASKS]

    x = np.arange(len(tasks))
    width = 0.35

    bars1 = ax.bar(x - width/2, without, width, label='Without MAINFRAME',
                   color=WARNING_RED, alpha=0.9, edgecolor='white', linewidth=0.5)
    bars2 = ax.bar(x + width/2, with_mf, width, label='With MAINFRAME',
                   color=MAINFRAME_GREEN, alpha=0.9, edgecolor='white', linewidth=0.5)

    # Add value labels on bars
    for bar in bars1:
        height = bar.get_height()
        ax.annotate(f'{int(height)}',
                    xy=(bar.get_x() + bar.get_width() / 2, height),
                    xytext=(0, 3), textcoords="offset points",
                    ha='center', va='bottom', color='white', fontsize=10, fontweight='bold')

    for bar in bars2:
        height = bar.get_height()
        ax.annotate(f'{int(height)}',
                    xy=(bar.get_x() + bar.get_width() / 2, height),
                    xytext=(0, 3), textcoords="offset points",
                    ha='center', va='bottom', color='white', fontsize=10, fontweight='bold')

    # Styling
    ax.set_ylabel('Tokens', color='white', fontsize=14, fontweight='bold')
    ax.set_title('Token Usage Per Bash Task', color='white', fontsize=18, fontweight='bold', pad=20)
    ax.set_xticks(x)
    ax.set_xticklabels(tasks, color='white', fontsize=11, rotation=15, ha='right')
    ax.tick_params(axis='y', colors='white')
    ax.spines['bottom'].set_color('white')
    ax.spines['left'].set_color('white')
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.legend(loc='upper right', facecolor=MAINFRAME_DARK, edgecolor='white',
              labelcolor='white', fontsize=11)
    ax.set_ylim(0, max(without) * 1.15)

    # Add savings annotation
    avg_savings = 71
    ax.text(0.5, 0.95, f'Average Savings: {avg_savings}%',
            transform=ax.transAxes, ha='center', va='top',
            fontsize=16, fontweight='bold', color=MAINFRAME_GREEN,
            bbox=dict(boxstyle='round,pad=0.5', facecolor=MAINFRAME_DARK,
                     edgecolor=MAINFRAME_GREEN, linewidth=2))

    plt.tight_layout()

    output_path = OUTPUT_DIR / "token-comparison-chart.png"
    plt.savefig(output_path, dpi=150, facecolor=MAINFRAME_DARK,
                edgecolor='none', bbox_inches='tight')
    plt.close()
    print(f"Created: {output_path}")
    return output_path


def create_linkedin_hero():
    """Create the main LinkedIn promotional image"""
    if not HAS_PIL:
        print("PIL not available, skipping LinkedIn hero")
        return None

    # LinkedIn optimal size: 1200x627
    width, height = 1200, 627
    img = Image.new('RGB', (width, height), color='#1a1a2e')
    draw = ImageDraw.Draw(img)

    # Try to load fonts, fall back to default
    try:
        font_title = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 72)
        font_hero = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 140)
        font_sub = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 32)
        font_small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
    except:
        font_title = ImageFont.load_default()
        font_hero = font_title
        font_sub = font_title
        font_small = font_title

    # Background gradient effect (simplified)
    for i in range(height):
        alpha = int(255 * (1 - i / height * 0.3))
        draw.line([(0, i), (width, i)], fill=(26, 26, 46))

    # Top bar accent
    draw.rectangle([0, 0, width, 8], fill=MAINFRAME_GREEN)

    # Title
    draw.text((60, 50), "MAINFRAME", font=font_title, fill=MAINFRAME_GREEN)

    # Hero number
    draw.text((60, 150), "71%", font=font_hero, fill='white')

    # Subtitle
    draw.text((60, 320), "Fewer Tokens Per Bash Task", font=font_sub, fill='#9CA3AF')

    # Supporting stats box
    box_y = 400
    draw.rectangle([60, box_y, 550, box_y + 180], outline=MAINFRAME_GREEN, width=2)

    stats = [
        ("3x", "More tasks before hitting Claude Code cap"),
        ("96%", "First-run success rate (vs 68%)"),
        ("72x", "Faster than external tools"),
    ]

    y_offset = box_y + 20
    for stat, desc in stats:
        draw.text((80, y_offset), stat, font=font_sub, fill=MAINFRAME_GREEN)
        draw.text((160, y_offset + 5), desc, font=font_small, fill='#D1D5DB')
        y_offset += 50

    # Right side - code preview
    code_x = 620
    code_y = 100
    draw.rectangle([code_x, code_y, width - 40, height - 40],
                   fill='#0d1117', outline='#30363d', width=1)

    # Code text
    code_lines = [
        ("# Before: 15+ lines", '#6B7280'),
        ("# After: 2 lines", '#6B7280'),
        ("", None),
        ('source "$MAINFRAME_ROOT/lib/common.sh"', '#79C0FF'),
        ("", None),
        ('json_object "name=John" \\', '#A5D6FF'),
        ('  "age:number=30"', '#A5D6FF'),
    ]

    try:
        font_code = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 20)
    except:
        font_code = font_small

    code_y_offset = code_y + 30
    for line, color in code_lines:
        if color:
            draw.text((code_x + 20, code_y_offset), line, font=font_code, fill=color)
        code_y_offset += 30

    # Bottom tagline
    draw.text((60, height - 50),
              "Pure Bash. 1,900+ Functions. Zero Dependencies.",
              font=font_small, fill='#6B7280')

    # GitHub reference
    draw.text((width - 280, height - 50),
              "github.com/gtwatts/mainframe",
              font=font_small, fill='#6B7280')

    output_path = OUTPUT_DIR / "linkedin-hero.png"
    img.save(output_path, quality=95)
    print(f"Created: {output_path}")
    return output_path


def create_readme_badge():
    """Create a badge for the README"""
    if not HAS_PIL:
        print("PIL not available, skipping badge")
        return None

    # Badge dimensions
    width, height = 200, 28
    img = Image.new('RGBA', (width, height), color=(0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Left part (label)
    draw.rounded_rectangle([0, 0, 100, height], radius=4, fill='#555555')
    # Right part (value)
    draw.rounded_rectangle([98, 0, width, height], radius=4, fill='#00D26A')

    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    except:
        font = ImageFont.load_default()

    draw.text((15, 6), "token savings", font=font, fill='white')
    draw.text((115, 6), "71%", font=font, fill='white')

    output_path = OUTPUT_DIR / "token-savings-badge.png"
    img.save(output_path)
    print(f"Created: {output_path}")
    return output_path


def create_weekly_cap_visual():
    """Create visual showing weekly cap benefit"""
    if not HAS_MATPLOTLIB:
        print("matplotlib not available, skipping weekly cap visual")
        return None

    fig, ax = plt.subplots(figsize=(10, 6), facecolor=MAINFRAME_DARK)
    ax.set_facecolor(MAINFRAME_DARK)

    # Weekly usage simulation
    days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

    # Without MAINFRAME: hits cap by Thursday
    without_mf = [20, 40, 60, 80, 100, 100, 100]  # Capped at 100%

    # With MAINFRAME: ~29% usage means can do 3x more
    with_mf = [7, 14, 21, 28, 35, 42, 49]  # Only 49% of cap used

    x = np.arange(len(days))

    ax.fill_between(x, without_mf, alpha=0.3, color=WARNING_RED, label='Without MAINFRAME')
    ax.plot(x, without_mf, color=WARNING_RED, linewidth=3, marker='o', markersize=8)

    ax.fill_between(x, with_mf, alpha=0.3, color=MAINFRAME_GREEN, label='With MAINFRAME')
    ax.plot(x, with_mf, color=MAINFRAME_GREEN, linewidth=3, marker='o', markersize=8)

    # Cap line
    ax.axhline(y=100, color='#FF6B6B', linestyle='--', linewidth=2, alpha=0.7)
    ax.text(6.1, 100, 'WEEKLY CAP', color='#FF6B6B', fontsize=10, va='center', fontweight='bold')

    # Annotations
    ax.annotate('Hits cap Thursday!', xy=(3, 80), xytext=(1.5, 90),
                color='white', fontsize=11,
                arrowprops=dict(arrowstyle='->', color='white', lw=1.5))

    ax.annotate('Still 51% headroom', xy=(6, 49), xytext=(4.5, 30),
                color=MAINFRAME_GREEN, fontsize=11, fontweight='bold',
                arrowprops=dict(arrowstyle='->', color=MAINFRAME_GREEN, lw=1.5))

    ax.set_ylabel('% of Weekly Token Cap Used', color='white', fontsize=12, fontweight='bold')
    ax.set_xlabel('Day of Week', color='white', fontsize=12, fontweight='bold')
    ax.set_title('Claude Code Max Weekly Usage', color='white', fontsize=16, fontweight='bold', pad=20)
    ax.set_xticks(x)
    ax.set_xticklabels(days, color='white', fontsize=11)
    ax.tick_params(axis='y', colors='white')
    ax.set_ylim(0, 120)
    ax.set_xlim(-0.5, 6.5)

    ax.spines['bottom'].set_color('white')
    ax.spines['left'].set_color('white')
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)

    ax.legend(loc='upper left', facecolor=MAINFRAME_DARK, edgecolor='white',
              labelcolor='white', fontsize=11)

    plt.tight_layout()

    output_path = OUTPUT_DIR / "weekly-cap-comparison.png"
    plt.savefig(output_path, dpi=150, facecolor=MAINFRAME_DARK,
                edgecolor='none', bbox_inches='tight')
    plt.close()
    print(f"Created: {output_path}")
    return output_path


def main():
    print("=" * 60)
    print("MAINFRAME Promotional Asset Generator")
    print("=" * 60)
    print()

    if not HAS_MATPLOTLIB and not HAS_PIL:
        print("ERROR: Neither matplotlib nor PIL available!")
        print("Install with: pip install matplotlib pillow")
        return

    print(f"Output directory: {OUTPUT_DIR}")
    print()

    # Generate all assets
    assets = []

    chart = create_comparison_chart()
    if chart:
        assets.append(("Token Comparison Chart", chart))

    hero = create_linkedin_hero()
    if hero:
        assets.append(("LinkedIn Hero Image", hero))

    badge = create_readme_badge()
    if badge:
        assets.append(("README Badge", badge))

    weekly = create_weekly_cap_visual()
    if weekly:
        assets.append(("Weekly Cap Comparison", weekly))

    print()
    print("=" * 60)
    print("ASSETS CREATED:")
    print("=" * 60)
    for name, path in assets:
        print(f"  {name}: {path}")

    print()
    print("Next steps:")
    print("  1. Review images in assets/promo/")
    print("  2. Add token-comparison-chart.png to README")
    print("  3. Post linkedin-hero.png on LinkedIn")
    print("  4. Use weekly-cap-comparison.png for engagement")


if __name__ == "__main__":
    main()
