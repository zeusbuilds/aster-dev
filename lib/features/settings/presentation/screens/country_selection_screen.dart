import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Screen for selecting a country
///
/// Displays a scrollable list of countries with flags and names
class CountrySelectionScreen extends StatefulWidget {
  const CountrySelectionScreen({super.key});

  @override
  State<CountrySelectionScreen> createState() => _CountrySelectionScreenState();
}

class _CountrySelectionScreenState extends State<CountrySelectionScreen> {
  final ScrollController _scrollController = ScrollController();
  List<CountryModel> _countries = [];
  bool _isLoading = true;
  String? _error;
  String? _selectedCountryCode;

  @override
  void initState() {
    super.initState();
    _loadCountries();
    // TODO: Load selected country from storage
  }

  Future<void> _loadCountries() async {
    try {
      final countries = await CountryModel.getAllSorted();
      setState(() {
        _countries = countries;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onCountrySelected(CountryModel country) {
    setState(() {
      _selectedCountryCode = country.code;
    });
    // TODO: Save selected country and navigate back
    Navigator.of(context).pop(country);
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final textTheme = context.textTheme;

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(title: 'Select Country', leadingIcon: true),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: context.colorScheme.primary,
              ),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error loading countries',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  CustomButton(text: 'Retry', onTap: _loadCountries),
                ],
              ),
            )
          : ScrollbarTheme(
              data: ScrollbarThemeData(
                thumbColor: WidgetStateProperty.all(
                  context.colorScheme.primary,
                ),
              ),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: false,
                child: ListView.separated(
                  controller: _scrollController,
                  padding: EdgeInsets.only(
                    bottom: spacing.bottomSafeRaw(context),
                  ),
                  itemCount: _countries.length,
                  separatorBuilder: (context, index) =>
                      const AsterDivider.inset(),
                  itemBuilder: (context, index) {
                    final country = _countries[index];

                    return CountrySelectOptionRow(
                      country: country,
                      selected: int.parse(_selectedCountryCode ?? '0'),
                      onTap: () {
                        _onCountrySelected(country);
                      },
                    );
                  },
                ),
              ),
            ),
    );
  }
}
