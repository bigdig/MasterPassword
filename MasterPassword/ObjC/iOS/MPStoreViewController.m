//
//  MPPreferencesViewController.m
//  MasterPassword-iOS
//
//  Created by Maarten Billemont on 04/06/12.
//  Copyright (c) 2012 Lyndir. All rights reserved.
//

#import "MPStoreViewController.h"
#import "MPiOSAppDelegate.h"
#import "UIColor+Expanded.h"
#import "MPAppDelegate_InApp.h"

PearlEnum( MPDevelopmentFuelConsumption,
        MPDevelopmentFuelConsumptionQuarterly, MPDevelopmentFuelConsumptionMonthly, MPDevelopmentFuelWeekly );

@interface MPStoreViewController()<MPInAppDelegate>

@property(nonatomic, strong) NSNumberFormatter *currencyFormatter;
@property(nonatomic, strong) NSArray *products;

@end

@implementation MPStoreViewController

- (void)viewDidLoad {

    [super viewDidLoad];

    self.currencyFormatter = [NSNumberFormatter new];
    self.currencyFormatter.numberStyle = NSNumberFormatterCurrencyStyle;

    self.tableView.tableHeaderView = [UIView new];
    self.tableView.tableFooterView = [UIView new];
    self.tableView.estimatedRowHeight = 400;
    self.view.backgroundColor = [UIColor clearColor];
}

- (void)viewWillAppear:(BOOL)animated {

    [super viewWillAppear:animated];

    self.tableView.contentInset = UIEdgeInsetsMake( 64, 0, 49, 0 );

    [self reloadCellsHiding:self.allCellsBySection[0] showing:nil];
    [self.allCellsBySection[0] enumerateObjectsUsingBlock:^(MPStoreProductCell *cell, NSUInteger idx, BOOL *stop) {
        if ([cell isKindOfClass:[MPStoreProductCell class]]) {
            cell.purchasedIndicator.alpha = 0;
            [cell.activityIndicator stopAnimating];
        }
    }];

    PearlAddNotificationObserver( NSUserDefaultsDidChangeNotification, nil, [NSOperationQueue mainQueue],
            ^(MPStoreViewController *self, NSNotification *note) {
                [self updateProducts];
                [self updateFuel];
            } );
    [[MPiOSAppDelegate get] registerProductsObserver:self];
    [self updateFuel];
}

- (void)viewWillDisappear:(BOOL)animated {

    [super viewWillDisappear:animated];

    PearlRemoveNotificationObservers();
}

#pragma mark - UITableViewDelegate

- (MPStoreProductCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    MPStoreProductCell *cell = (MPStoreProductCell *)[super tableView:tableView cellForRowAtIndexPath:indexPath];
    if (cell.contentView.translatesAutoresizingMaskIntoConstraints) {
        cell.contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addConstraint:
                [NSLayoutConstraint constraintWithItem:cell attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual
                                                toItem:cell.contentView attribute:NSLayoutAttributeWidth multiplier:1 constant:0]];
    }

    if (indexPath.section == 0)
        cell.selectionStyle = [[MPiOSAppDelegate get] isFeatureUnlocked:[self productForCell:cell].productIdentifier]?
                              UITableViewCellSelectionStyleDefault: UITableViewCellSelectionStyleNone;

    if (cell.selectionStyle != UITableViewCellSelectionStyleNone) {
        cell.selectedBackgroundView = [[UIView alloc] initWithFrame:cell.bounds];
        cell.selectedBackgroundView.backgroundColor = [UIColor colorWithRGBAHex:0x78DDFB33];
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {

    UITableViewCell *cell = [self tableView:tableView cellForRowAtIndexPath:indexPath];
    [cell layoutIfNeeded];

    return cell.contentView.bounds.size.height;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    if (![[MPAppDelegate_Shared get] canMakePayments]) {
        [PearlAlert showAlertWithTitle:@"Store Not Set Up" message:
                        @"Try logging using the App Store or from Settings."
                             viewStyle:UIAlertViewStyleDefault initAlert:nil
                     tappedButtonBlock:nil cancelTitle:@"Thanks" otherTitles:nil];
        return;
    }

    MPStoreProductCell *cell = (MPStoreProductCell *)[self tableView:tableView cellForRowAtIndexPath:indexPath];
    SKProduct *product = [self productForCell:cell];

    if (product)
        [[MPAppDelegate_Shared get] purchaseProductWithIdentifier:product.productIdentifier
                                                         quantity:[self quantityForProductIdentifier:product.productIdentifier]];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Actions

- (IBAction)toggleFuelConsumption:(id)sender {

    NSUInteger fuelConsumption = [[MPiOSConfig get].developmentFuelConsumption unsignedIntegerValue];
    [MPiOSConfig get].developmentFuelConsumption = @((fuelConsumption + 1) % MPDevelopmentFuelConsumptionCount);
    [self updateProducts];
}

- (IBAction)restorePurchases:(id)sender {

    [PearlAlert showAlertWithTitle:@"Restore Previous Purchases" message:
                    @"This will check with Apple to find and activate any purchases you made from other devices."
                         viewStyle:UIAlertViewStyleDefault initAlert:nil
                 tappedButtonBlock:^(UIAlertView *alert, NSInteger buttonIndex) {
                     if (buttonIndex == [alert cancelButtonIndex])
                         return;

                     [[MPAppDelegate_Shared get] restoreCompletedTransactions];
                 } cancelTitle:@"Cancel" otherTitles:@"Find Purchases", nil];
}

#pragma mark - MPInAppDelegate

- (void)updateWithProducts:(NSArray *)products {

    self.products = products;

    [self updateProducts];
}

- (void)updateWithTransaction:(SKPaymentTransaction *)transaction {

    MPStoreProductCell *cell = [self cellForProductIdentifier:transaction.payment.productIdentifier];
    if (!cell)
        return;

    switch (transaction.transactionState) {
        case SKPaymentTransactionStatePurchasing:
            [cell.activityIndicator startAnimating];
            break;
        case SKPaymentTransactionStatePurchased:
            [cell.activityIndicator stopAnimating];
            break;
        case SKPaymentTransactionStateFailed:
            [cell.activityIndicator stopAnimating];
            break;
        case SKPaymentTransactionStateRestored:
            [cell.activityIndicator stopAnimating];
            break;
        case SKPaymentTransactionStateDeferred:
            [cell.activityIndicator startAnimating];
            break;
    }
}

#pragma mark - Private

- (SKProduct *)productForCell:(MPStoreProductCell *)cell {

    for (SKProduct *product in self.products)
        if ([self cellForProductIdentifier:product.productIdentifier] == cell)
            return product;

    return nil;
}

- (MPStoreProductCell *)cellForProductIdentifier:(NSString *)productIdentifier {

    if ([productIdentifier isEqualToString:MPProductGenerateLogins])
        return self.generateLoginCell;
    if ([productIdentifier isEqualToString:MPProductGenerateAnswers])
        return self.generateAnswersCell;
    if ([productIdentifier isEqualToString:MPProductFuel])
        return self.fuelCell;

    return nil;
}

- (void)updateProducts {

    NSMutableArray *showCells = [NSMutableArray array];
    NSMutableArray *hideCells = [NSMutableArray array];
    [hideCells addObjectsFromArray:self.allCellsBySection[0]];

    for (SKProduct *product in self.products) {
        [self showCellForProductWithIdentifier:MPProductGenerateLogins ifProduct:product showingCells:showCells];
        [self showCellForProductWithIdentifier:MPProductGenerateAnswers ifProduct:product showingCells:showCells];
        [self showCellForProductWithIdentifier:MPProductFuel ifProduct:product showingCells:showCells];
    }

    [hideCells removeObjectsInArray:showCells];
    if ([self.tableView numberOfRowsInSection:0])
        [self updateCellsHiding:hideCells showing:showCells animation:UITableViewRowAnimationAutomatic];
    else
        [self updateCellsHiding:hideCells showing:showCells animation:UITableViewRowAnimationNone];
}

- (void)updateFuel {

    CGFloat weeklyFuelConsumption = [self weeklyFuelConsumption]; /* consume x fuel / week */
    CGFloat fuel = [[MPiOSConfig get].developmentFuel floatValue]; /* x fuel left */
    NSTimeInterval fuelSecondsElapsed = [[MPiOSConfig get].developmentFuelChecked timeIntervalSinceNow];
    if (fuelSecondsElapsed > 3600) {
        NSTimeInterval weeksElapsed = fuelSecondsElapsed / (3600 * 24 * 7 /* 1 week */); /* x weeks elapsed */
        fuel -= weeklyFuelConsumption * weeksElapsed;
        [MPiOSConfig get].developmentFuel = @(fuel);
    }

    CGFloat fuelRatio = weeklyFuelConsumption == 0? 0: fuel / weeklyFuelConsumption; /* x weeks worth of fuel left */
    [self.fuelMeterConstraint updateConstant:MIN( 0.5f, fuelRatio - 0.5f ) * 160]; /* -80pt = 0 weeks left, 80pt = >=1 week left */
}

- (CGFloat)weeklyFuelConsumption {

    switch ((MPDevelopmentFuelConsumption)[[MPiOSConfig get].developmentFuelConsumption unsignedIntegerValue]) {
        case MPDevelopmentFuelConsumptionQuarterly:
            [self.fuelSpeedButton setTitle:@"1h / quarter" forState:UIControlStateNormal];
            return 1.f / 12 /* 12 weeks */;
        case MPDevelopmentFuelConsumptionMonthly:
            [self.fuelSpeedButton setTitle:@"1h / month" forState:UIControlStateNormal];
            return 1.f / 4 /* 4 weeks */;
        case MPDevelopmentFuelWeekly:
            [self.fuelSpeedButton setTitle:@"1h / week" forState:UIControlStateNormal];
            return 1.f;
    }

    return 0;
}

- (void)showCellForProductWithIdentifier:(NSString *)productIdentifier ifProduct:(SKProduct *)product
                            showingCells:(NSMutableArray *)showCells {

    if (![product.productIdentifier isEqualToString:productIdentifier])
        return;

    MPStoreProductCell *cell = [self cellForProductIdentifier:productIdentifier];
    [showCells addObject:cell];

    self.currencyFormatter.locale = product.priceLocale;
    BOOL purchased = [[MPiOSAppDelegate get] isFeatureUnlocked:productIdentifier];
    NSInteger quantity = [self quantityForProductIdentifier:productIdentifier];
    cell.priceLabel.text = purchased? @"": [self.currencyFormatter stringFromNumber:@([product.price floatValue] * quantity)];
    cell.purchasedIndicator.alpha = purchased? 1: 0;
}

- (NSInteger)quantityForProductIdentifier:(NSString *)productIdentifier {

    if ([productIdentifier isEqualToString:MPProductFuel])
        return (NSInteger)(MP_FUEL_HOURLY_RATE * [self weeklyFuelConsumption]);

    return 1;
}

@end

@implementation MPStoreProductCell
@end