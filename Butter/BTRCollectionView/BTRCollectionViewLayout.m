//
//  BTRCollectionViewLayout.m
//
//  Original Source: Copyright (c) 2012 Peter Steinberger. All rights reserved.
//  AppKit Port: Copyright (c) 2012 Indragie Karunaratne and Jonathan Willing. All rights reserved.
//

#import "BTRCollectionView.h"
#import "BTRCollectionViewLayout.h"
#import "BTRGeometryAdditions.h"
#import "NSIndexPath+BTRAdditions.h"

@interface BTRCollectionView()
- (id)currentUpdate;
- (NSDictionary *)visibleViewsDict;
- (BTRCollectionViewData *)collectionViewData;
- (CGRect)visibleBoundRects; // visibleBounds is flagged as private API (wtf)
@end

@interface BTRCollectionReusableView()
- (void)setIndexPath:(NSIndexPath *)indexPath;
@end

@class BTRCollectionViewUpdateItem;
@interface BTRCollectionViewUpdateItem()
- (BOOL)isSectionOperation;
@end

@interface BTRCollectionViewLayoutAttributes() {
    struct {
        unsigned int isCellKind:1;
        unsigned int isDecorationView:1;
        unsigned int isHidden:1;
    } _layoutFlags;
}
@property (nonatomic, copy) NSString *elementKind;
@property (nonatomic, copy) NSString *reuseIdentifier;
@end

@interface BTRCollectionViewUpdateItem()
-(NSIndexPath*) indexPath;
@end

@implementation BTRCollectionViewLayoutAttributes

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Static

+ (instancetype)layoutAttributesForCellWithIndexPath:(NSIndexPath *)indexPath {
    BTRCollectionViewLayoutAttributes *attributes = [self new];
    attributes.elementKind = BTRCollectionElementKindCell;
    attributes.indexPath = indexPath;
    return attributes;
}

+ (instancetype)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind withIndexPath:(NSIndexPath *)indexPath {
    BTRCollectionViewLayoutAttributes *attributes = [self new];
    attributes.elementKind = elementKind;
    attributes.indexPath = indexPath;
    return attributes;
}

+ (instancetype)layoutAttributesForDecorationViewWithReuseIdentifier:(NSString *)reuseIdentifier withIndexPath:(NSIndexPath *)indexPath {
    BTRCollectionViewLayoutAttributes *attributes = [self new];
    attributes.elementKind = BTRCollectionElementKindDecorationView;
    attributes.reuseIdentifier = reuseIdentifier;
    attributes.indexPath = indexPath;
    return attributes;
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)init {
    if((self = [super init])) {
        _alpha = 1.f;
        _transform3D = CATransform3DIdentity;
    }
    return self;
}

- (NSUInteger)hash {
    return ([_elementKind hash] * 31) + [_indexPath hash];
}

- (BOOL)isEqual:(id)other {
    if ([other isKindOfClass:[self class]]) {
        BTRCollectionViewLayoutAttributes *otherLayoutAttributes = (BTRCollectionViewLayoutAttributes *)other;
        if ([_elementKind isEqual:otherLayoutAttributes.elementKind] && [_indexPath isEqual:otherLayoutAttributes.indexPath]) {
            return YES;
        }
    }
    return NO;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame:%@ indexPath:%@ elementKind:%@>", NSStringFromClass([self class]), self, BTRNSStringFromCGRect(self.frame), self.indexPath, self.elementKind];
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (BTRCollectionViewItemType)representedElementCategory {
    if ([self.elementKind isEqualToString:BTRCollectionElementKindCell]) {
        return BTRCollectionViewItemTypeCell;
    }else if([self.elementKind isEqualToString:BTRCollectionElementKindDecorationView]) {
        return BTRCollectionViewItemTypeDecorationView;
    }else {
        return BTRCollectionViewItemTypeSupplementaryView;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (NSString *)representedElementKind {
    return self.elementKind;
}

- (BOOL)isDecorationView {
    return self.representedElementCategory == BTRCollectionViewItemTypeDecorationView;
}

- (BOOL)isSupplementaryView {
    return self.representedElementCategory == BTRCollectionViewItemTypeSupplementaryView;
}

- (BOOL)isCell {
    return self.representedElementCategory == BTRCollectionViewItemTypeCell;
}

- (void)setSize:(CGSize)size {
    _size = size;
    _frame = (CGRect){_frame.origin, _size};
}

- (void)setCenter:(CGPoint)center {
    _center = center;
    _frame = (CGRect){{_center.x - _frame.size.width / 2, _center.y - _frame.size.height / 2}, _frame.size};
}

- (void)setFrame:(CGRect)frame {
    _frame = frame;
    _size = _frame.size;
    _center = (CGPoint){CGRectGetMidX(_frame), CGRectGetMidY(_frame)};
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    BTRCollectionViewLayoutAttributes *layoutAttributes = [[self class] new];
    layoutAttributes.indexPath = self.indexPath;
    layoutAttributes.elementKind = self.elementKind;
    layoutAttributes.reuseIdentifier = self.reuseIdentifier;
    layoutAttributes.frame = self.frame;
    layoutAttributes.center = self.center;
    layoutAttributes.size = self.size;
    layoutAttributes.transform3D = self.transform3D;
    layoutAttributes.alpha = self.alpha;
    layoutAttributes.zIndex = self.zIndex;
    layoutAttributes.hidden = self.isHidden;
    return layoutAttributes;
}
@end


@interface BTRCollectionViewLayout() {
    __unsafe_unretained BTRCollectionView *_collectionView;
    CGSize _collectionViewBoundsSize;
    NSMutableDictionary *_initialAnimationLayoutAttributesDict;
    NSMutableDictionary *_finalAnimationLayoutAttributesDict;
    NSMutableIndexSet *_deletedSectionsSet;
    NSMutableIndexSet *_insertedSectionsSet;
    NSMutableDictionary *_decorationViewClassDict;
    NSMutableDictionary *_decorationViewNibDict;
    NSMutableDictionary *_decorationViewExternalObjectsTables;
}
@property (nonatomic, unsafe_unretained) BTRCollectionView *collectionView;
@end

NSString *const BTRCollectionViewLayoutAwokeFromNib = @"BTRCollectionViewLayoutAwokeFromNib";

@implementation BTRCollectionViewLayout

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)init {
    if((self = [super init])) {
        _decorationViewClassDict = [NSMutableDictionary new];
        _decorationViewNibDict = [NSMutableDictionary new];
        _decorationViewExternalObjectsTables = [NSMutableDictionary new];
        _initialAnimationLayoutAttributesDict = [NSMutableDictionary new];
        _finalAnimationLayoutAttributesDict = [NSMutableDictionary new];
        _insertedSectionsSet = [NSMutableIndexSet new];
        _deletedSectionsSet = [NSMutableIndexSet new];

        [[NSNotificationCenter defaultCenter] postNotificationName:BTRCollectionViewLayoutAwokeFromNib object:self];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
}

- (void)setCollectionView:(BTRCollectionView *)collectionView {
    if (collectionView != _collectionView) {
        _collectionView = collectionView;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Invalidating the Layout

- (void)invalidateLayout {
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return NO; // return YES to requery the layout for geometry information
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Providing Layout Attributes

- (void)prepareLayout {
}

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect {
    return nil;
}

- (BTRCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    return nil;
}

- (BTRCollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    return nil;
}

- (BTRCollectionViewLayoutAttributes *)layoutAttributesForDecorationViewWithReuseIdentifier:(NSString*)identifier atIndexPath:(NSIndexPath *)indexPath {
    return nil;
}

// return a point at which to rest after scrolling - for layouts that want snap-to-point scrolling behavior
- (CGPoint)targetContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset withScrollingVelocity:(CGPoint)velocity {
    return proposedContentOffset;
}

- (CGSize)collectionViewContentSize {
    return CGSizeZero;
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Responding to Collection View Updates

- (void)prepareForCollectionViewUpdates:(NSArray *)updateItems {
    NSDictionary* update = [_collectionView currentUpdate];

    for (BTRCollectionReusableView *view in [[_collectionView visibleViewsDict] objectEnumerator]) {
        BTRCollectionViewLayoutAttributes *attr = [view.layoutAttributes copy];

        BTRCollectionViewData* oldModel = update[@"oldModel"];
        NSInteger index = [oldModel globalIndexForItemAtIndexPath:[attr indexPath]];

        if(index != NSNotFound) {
            index = [update[@"oldToNewIndexMap"][index] intValue];
            if(index != NSNotFound) {
                [attr setIndexPath:[update[@"newModel"] indexPathForItemAtGlobalIndex:index]];
                [_initialAnimationLayoutAttributesDict setObject:attr
                                                          forKey:[BTRCollectionViewItemKey collectionItemKeyForLayoutAttributes:attr]];
            }
        }
    }

    BTRCollectionViewData* collectionViewData = [_collectionView collectionViewData];

    CGRect bounds = [_collectionView visibleBoundRects];

    for (BTRCollectionViewLayoutAttributes* attr in [collectionViewData layoutAttributesForElementsInRect:bounds]) {
        NSInteger index = [collectionViewData globalIndexForItemAtIndexPath:attr.indexPath];

        index = [update[@"newToOldIndexMap"][index] intValue];
        if(index != NSNotFound) {
            BTRCollectionViewLayoutAttributes* finalAttrs = [attr copy];
            [finalAttrs setIndexPath:[update[@"oldModel"] indexPathForItemAtGlobalIndex:index]];
            [finalAttrs setAlpha:0];
            [_finalAnimationLayoutAttributesDict setObject:finalAttrs
                                                    forKey:[BTRCollectionViewItemKey collectionItemKeyForLayoutAttributes:finalAttrs]];
        }
    }

    for(BTRCollectionViewUpdateItem* updateItem in updateItems) {
        BTRCollectionUpdateAction action = updateItem.updateAction;

        if([updateItem isSectionOperation]) {
            if(action == BTRCollectionUpdateActionReload) {
                [_deletedSectionsSet addIndex:[[updateItem indexPathBeforeUpdate] section]];
                [_insertedSectionsSet addIndex:[updateItem indexPathAfterUpdate].section];
            }
            else {
                NSMutableIndexSet *indexSet = action == BTRCollectionUpdateActionInsert ? _insertedSectionsSet : _deletedSectionsSet;
                [indexSet addIndex:[updateItem indexPath].section];
            }
        }
        else {
            if(action == BTRCollectionUpdateActionDelete) {
                BTRCollectionViewItemKey *key = [BTRCollectionViewItemKey collectionItemKeyForCellWithIndexPath:
                                                 [updateItem indexPathBeforeUpdate]];

                BTRCollectionViewLayoutAttributes *attrs = [[_finalAnimationLayoutAttributesDict objectForKey:key]copy];

                if(attrs) {
                    [attrs setAlpha:0];
                    [_finalAnimationLayoutAttributesDict setObject:attrs
                                                            forKey:key];
                }
            }
            else if(action == BTRCollectionUpdateActionReload || action == BTRCollectionUpdateActionInsert) {
                BTRCollectionViewItemKey *key = [BTRCollectionViewItemKey collectionItemKeyForCellWithIndexPath:
                                                 [updateItem indexPathAfterUpdate]];
                BTRCollectionViewLayoutAttributes *attrs = [[_initialAnimationLayoutAttributesDict objectForKey:key] copy];

                if(attrs) {
                    [attrs setAlpha:0];
                    [_initialAnimationLayoutAttributesDict setObject:attrs forKey:key];
                }
            }
        }
    }
}

- (BTRCollectionViewLayoutAttributes *)initialLayoutAttributesForAppearingItemAtIndexPath:(NSIndexPath*)itemIndexPath {
    BTRCollectionViewLayoutAttributes* attrs = [_initialAnimationLayoutAttributesDict objectForKey:
                                                [BTRCollectionViewItemKey collectionItemKeyForCellWithIndexPath:itemIndexPath]];

    if([_insertedSectionsSet containsIndex:[itemIndexPath section]]) {
        attrs = [attrs copy];
        [attrs setAlpha:0];
    }
    return attrs;
}

- (BTRCollectionViewLayoutAttributes *)finalLayoutAttributesForDisappearingItemAtIndexPath:(NSIndexPath *)itemIndexPath {
    BTRCollectionViewLayoutAttributes* attrs = [_finalAnimationLayoutAttributesDict objectForKey:
                                                [BTRCollectionViewItemKey collectionItemKeyForCellWithIndexPath:itemIndexPath]];

    if([_deletedSectionsSet containsIndex:[itemIndexPath section]]) {
        attrs = [attrs copy];
        [attrs setAlpha:0];
    }
    return attrs;

}

- (BTRCollectionViewLayoutAttributes *)initialLayoutAttributesForInsertedSupplementaryElementOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)elementIndexPath {
    return nil;
}

- (BTRCollectionViewLayoutAttributes *)finalLayoutAttributesForDeletedSupplementaryElementOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)elementIndexPath {
    return nil;
}

- (void)finalizeCollectionViewUpdates {
    [_initialAnimationLayoutAttributesDict removeAllObjects];
    [_finalAnimationLayoutAttributesDict removeAllObjects];
    [_deletedSectionsSet removeAllIndexes];
    [_insertedSectionsSet removeAllIndexes];
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Registering Decoration Views

- (void)registerClass:(Class)viewClass forDecorationViewWithReuseIdentifier:(NSString *)identifier {
}

- (void)registerNib:(NSNib *)nib forDecorationViewWithReuseIdentifier:(NSString *)identifier {
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (void)setCollectionViewBoundsSize:(CGSize)size {
    _collectionViewBoundsSize = size;
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)coder {
    if((self = [self init])) {
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {}
@end