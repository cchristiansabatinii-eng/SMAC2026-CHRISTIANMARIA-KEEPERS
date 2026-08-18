import 'package:flutter/material.dart';

class KeepersColors {
  static const auraGround = Color(0xFFFFFAF2);
  static const auraBlush = Color(0xFFFFE8DF);
  static const auraIvory = Color(0xFFFFFDF8);
  static const backgroundFlatFallback = Color(0xFFF5E9DE);
  static const ink = Color(0xFF11110F);
  static const inkMuted = Color(0xFF6D6963);
  static const homeInk = Color(0xFF201810);
  static const homeTaupe = Color(0xFF8B7E70);
  static const homeGold = Color(0xFFBE8E20);
  static const homeGoldText = Color(0xFF8A650E);
  static const homeClay = Color(0xFFFF7A72);
  static const homeGreen = Color(0xFF5BD5AA);
  static const homeBlue = Color(0xFF78A8FF);
  static const homeMauve = Color(0xFFC99CFF);
  static const homeActionLine = Color(0xFFD4BBAC);
  static const homeLine = Color(0xFFDDCFBF);
  static const homeAvatarGold = Color(0xFFFFD563);
  static const legacyOlive = Color(0xFF7C835C);
  static const legacyOliveText = Color(0xFF646943);
  static const ground = Color(0xFF0B0A08);
  static const groundVignette = Color(0xFF171310);
  static const cream = Color(0xFFEFE7D4);
  static const brass = Color(0xFFC9A227);
  static const brassLight = Color(0xFFE3C560);
  static const memorialGold = Color(0xFFA89468);
  static const avatarBase = Color(0xFF14110C);

  // Reserved per-member colors, assigned round-robin at family setup.
  // A member KEEPS their color for life — never reassign once set.
  static const memberPalette = <Color>[
    Color(0xFF7BC950), // green
    Color(0xFFE4626F), // rose
    Color(0xFFE8873A), // orange
    Color(0xFF3EB8A5), // teal
    Color(0xFF5B9BD5), // blue
    Color(0xFF9B6BD5), // purple
  ];
}

class KeepersType {
  // Modern Society is the sole application typeface. Role-specific scale,
  // weight, tracking, and casing provide hierarchy without introducing a
  // second family. Keep the font bundled so private/offline use never falls
  // back to a network dependency.
  static const primary = 'ModernSociety';

  /// Canonical page and section heading, matching the family title on Home.
  static const heading = TextStyle(
    fontFamily: primary,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1,
    letterSpacing: .8,
  );
}

/// The canonical painted-text primitive for Keepers.
///
/// Source strings and accessibility labels keep their natural casing, while
/// the visual layer follows the product's title-case Modern Society system.
/// Keeping the original [Text.data] also avoids changing persisted family and
/// memory content merely to achieve the display treatment.
class KeepersText extends Text {
  const KeepersText(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });

  const KeepersText.rich(
    super.textSpan, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  }) : super.rich();

  @override
  Widget build(BuildContext context) {
    final visualStyle = (style ?? const TextStyle()).copyWith(
      fontFamily: KeepersType.primary,
    );
    final visual = textSpan == null
        ? Text(
            keepersTitleCase(data!),
            style: visualStyle,
            strutStyle: strutStyle,
            textAlign: textAlign,
            textDirection: textDirection,
            locale: locale,
            softWrap: softWrap,
            overflow: overflow,
            textScaler: textScaler,
            maxLines: maxLines,
            semanticsLabel: semanticsLabel ?? data,
            semanticsIdentifier: semanticsIdentifier,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior,
            selectionColor: selectionColor,
          )
        : Text.rich(
            _titleCaseSpan(textSpan!),
            style: visualStyle,
            strutStyle: strutStyle,
            textAlign: textAlign,
            textDirection: textDirection,
            locale: locale,
            softWrap: softWrap,
            overflow: overflow,
            textScaler: textScaler,
            maxLines: maxLines,
            semanticsLabel: semanticsLabel,
            semanticsIdentifier: semanticsIdentifier,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior,
            selectionColor: selectionColor,
          );

    // Calling the framework widget's build directly avoids adding a second
    // Text element. Tests and semantics can still address this source widget,
    // while RichText receives the transformed display copy.
    return visual.build(context);
  }
}

/// Applies the Keepers presentation casing without modifying source content.
///
/// Apostrophes remain part of the current word so names such as `O'NEILL`
/// render as `O'neill`; punctuation and whitespace begin a new word.
String keepersTitleCase(String value) {
  final result = StringBuffer();
  var atWordStart = true;
  var insideWord = false;

  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final lowercase = character.toLowerCase();
    final uppercase = character.toUpperCase();
    final isCasedLetter = lowercase != uppercase;
    final isDigit = rune >= 0x30 && rune <= 0x39;

    if (isCasedLetter) {
      result.write(atWordStart ? uppercase : lowercase);
      atWordStart = false;
      insideWord = true;
      continue;
    }

    result.write(character);
    if (isDigit) {
      atWordStart = false;
      insideWord = true;
    } else if ((character == "'" || character == '’') && insideWord) {
      atWordStart = false;
    } else {
      atWordStart = true;
      insideWord = false;
    }
  }

  return result.toString();
}

InlineSpan _titleCaseSpan(InlineSpan span) {
  if (span is! TextSpan) return span;
  return TextSpan(
    text: span.text == null ? null : keepersTitleCase(span.text!),
    children: span.children?.map(_titleCaseSpan).toList(growable: false),
    style: (span.style ?? const TextStyle()).copyWith(
      fontFamily: KeepersType.primary,
    ),
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
    onEnter: span.onEnter,
    onExit: span.onExit,
    semanticsLabel: span.semanticsLabel ?? span.text,
    semanticsIdentifier: span.semanticsIdentifier,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}
