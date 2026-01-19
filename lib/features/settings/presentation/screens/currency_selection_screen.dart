import 'package:aster/shared/shared.dart';
import 'package:aster/features/settings/presentation/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// Screen for selecting a currency
///
/// Displays a scrollable list of currencies with names, symbols, and codes
class CurrencySelectionScreen extends StatefulWidget {
  const CurrencySelectionScreen({super.key});

  @override
  State<CurrencySelectionScreen> createState() =>
      _CurrencySelectionScreenState();
}

class _CurrencySelectionScreenState extends State<CurrencySelectionScreen> {
  List<CurrencyModel> _currencies = [];
  bool _isLoading = true;
  String? _error;
  String? _selectedCurrencyCode;

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
    // TODO: Load selected currency from storage
  }

  Future<void> _loadCurrencies() async {
    try {
      final currencies = await CurrencyModel.getAllSorted();
      setState(() {
        _currencies = currencies;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onCurrencySelected(CurrencyModel currency) {
    setState(() {
      _selectedCurrencyCode = currency.code;
    });
    // TODO: Save selected currency and navigate back
    Navigator.of(context).pop(currency);
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;
    final textTheme = context.textTheme;

    return Scaffold(
      backgroundColor: colors.fill1,
      appBar: const CustomAppBar(title: 'Select Currency', leadingIcon: true),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.brand6))
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error loading currencies',
                    style: textTheme.bodyMedium?.copyWith(color: colors.text2),
                  ),
                  SizedBox(height: spacing.spacing16),
                  CustomButton(text: 'Retry', onTap: _loadCurrencies),
                ],
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.only(bottom: spacing.bottomSafeHeightRaw),
              itemCount: _currencies.length,
              separatorBuilder: (context, index) => Divider(
                color: colors.fill2,
                height: 1,
                thickness: 1,
                indent: spacing.spacing20,
              ),
              itemBuilder: (context, index) {
                final currency = _currencies[index];

                return CurrencySelectOptionRow(
                  currency: currency,
                  selected: _selectedCurrencyCode == currency.code ? 0 : -1,
                  onTap: () {
                    _onCurrencySelected(currency);
                  },
                );
              },
            ),
    );
  }
}
