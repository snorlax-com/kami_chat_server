/// Region/country for consent (EU/UK strict cookie, BIPA etc.).
/// Server should derive country from IP and return; app defaults to strict when unknown.
class RegionInfo {
  const RegionInfo({
    required this.country,
    required this.regionGroup,
  });

  final String country;
  final String regionGroup;

  bool get isEu => regionGroup == 'EU';
  bool get isUk => regionGroup == 'UK';
  bool get isStrictCookie => isEu || isUk;
}

/// EEA country codes (ISO2) for EU group.
const _eeaCountries = {
  'AT',
  'BE',
  'BG',
  'HR',
  'CY',
  'CZ',
  'DK',
  'EE',
  'FI',
  'FR',
  'DE',
  'GR',
  'HU',
  'IE',
  'IT',
  'LV',
  'LT',
  'LU',
  'MT',
  'NL',
  'PL',
  'PT',
  'RO',
  'SK',
  'SI',
  'ES',
  'SE',
  'IS',
  'LI',
  'NO',
};

String regionGroupFromCountry(String country) {
  final c = country.toUpperCase();
  if (c == 'GB') return 'UK';
  if (_eeaCountries.contains(c)) return 'EU';
  if (c == 'US') return 'US';
  return 'OTHER';
}
