import 'dart:async';

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
    unawaited(_loadCountries());
    // TODO: Load selected country from storage
  }

  Future<void> _loadCountries() async {
    try {
      final countries = await CountryModel.getAllSorted();
      if (!mounted) return;
      setState(() {
        _countries = countries;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.runtimeType.toString();
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
    final type = context.type;

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
                  Text('Error loading countries', style: type.errorMessage),
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
              child: SafeArea(
                top: false,
                minimum: EdgeInsets.only(bottom: spacing.lg),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: false,
                  child: ListView.separated(
                    controller: _scrollController,
                    itemCount: _countries.length,
                    separatorBuilder: (context, index) =>
                        const AsterDivider.inset(),
                    itemBuilder: (context, index) {
                      final country = _countries[index];

                      return CountrySelectOptionRow(
                        country: country,
                        selected: _selectedCountryCode == country.code,
                        onTap: () {
                          _onCountrySelected(country);
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }
}
