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
    final colors = context.colors;
    final textTheme = context.textTheme;

    return Scaffold(
      backgroundColor: colors.fill1,
      appBar: const CustomAppBar(title: 'Select Country', leadingIcon: true),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.brand6))
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error loading countries',
                    style: textTheme.bodyMedium?.copyWith(color: colors.text2),
                  ),
                  SizedBox(height: spacing.spacing16),
                  CustomButton(text: 'Retry', onTap: _loadCountries),
                ],
              ),
            )
          : ScrollbarTheme(
              data: ScrollbarThemeData(
                thumbColor: WidgetStateProperty.all(colors.brand6),
              ),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: false,
                child: ListView.separated(
                  controller: _scrollController,
                  padding: EdgeInsets.only(bottom: spacing.bottomSafeHeightRaw),
                  itemCount: _countries.length,
                  separatorBuilder: (context, index) => Divider(
                    color: colors.fill2,
                    height: 1,
                    thickness: 1,
                    indent: spacing.spacing20,
                  ),
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
