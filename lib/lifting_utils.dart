class LiftingUtils {
  // Wilks Score coefficients for men (kg)
  static const List<double> _menCoeffs = [
    -216.0475144,
    16.2606339,
    -0.002388645,
    -0.00113732,
    7.01863e-6,
    -1.291e-8,
  ];

  // Wilks Score coefficients for women (kg)
  static const List<double> _womenCoeffs = [
    594.31747775582,
    -27.23842536447,
    0.82112226871,
    -0.00930733913,
    4.731582e-5,
    -9.054e-8,
  ];

  // Calculate Wilks Score
  static double calculateWilksScore(
    double totalKg,
    double bodyweightKg,
    String gender,
  ) {
    if (bodyweightKg <= 0 || totalKg <= 0) return 0.0;

    final coeffs = gender.toLowerCase() == 'female' ? _womenCoeffs : _menCoeffs;
    double wilksCoeff =
        500.0 / _calculateWilksCoefficient(bodyweightKg, coeffs);
    return totalKg * wilksCoeff;
  }

  static double _calculateWilksCoefficient(
    double bodyweight,
    List<double> coeffs,
  ) {
    double coeff = coeffs[0];
    for (int i = 1; i < coeffs.length; i++) {
      coeff += coeffs[i] * _pow(bodyweight, i);
    }
    return coeff;
  }

  static double _pow(double base, int exp) {
    double result = 1.0;
    for (int i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }

  // Convert lbs to kg
  static double lbsToKg(double lbs) => lbs * 0.453592;

  // Convert kg to lbs
  static double kgToLbs(double kg) => kg * 2.20462;
}
