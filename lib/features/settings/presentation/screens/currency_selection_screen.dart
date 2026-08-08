import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

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
  final ScrollController _scrollController = ScrollController();
  List<CurrencyModel> _currencies = [];
  bool _isLoading = true;
  String? _error;
  String? _selectedCurrencyCode;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCurrencies());
    // TODO: Load selected currency from storage
  }

  Future<void> _loadCurrencies() async {
    try {
      final currencies = await CurrencyModel.getAllSorted();
      if (!mounted) return;
      setState(() {
        _currencies = currencies;
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
    final type = context.type;

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(title: 'Select Currency', leadingIcon: true),
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
                  Text('Error loading currencies', style: type.errorMessage),
                  SizedBox(height: spacing.lg),
                  CustomButton(text: 'Retry', onTap: _loadCurrencies),
                ],
              ),
            )
          : SafeArea(
              top: false,
              minimum: EdgeInsets.only(bottom: spacing.lg),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: false,
                child: ListView.separated(
                  controller: _scrollController,
                  itemCount: _currencies.length,
                  separatorBuilder: (context, index) =>
                      const AsterDivider.inset(),
                  itemBuilder: (context, index) {
                    final currency = _currencies[index];

                    return CurrencySelectOptionRow(
                      currency: currency,
                      selected: _selectedCurrencyCode == currency.code,
                      onTap: () {
                        _onCurrencySelected(currency);
                      },
                    );
                  },
                ),
              ),
            ),
    );
  }
}
