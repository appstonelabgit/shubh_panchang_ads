/// Height of the box the small native template is drawn in.
///
/// The iOS small template's media view is square and up to a quarter of the
/// ad's width: about 101 pt on a Pro Max card. In a 100 pt box it overflowed,
/// and AdMob's validator reported "advertiser assets outside native ad
/// view". 108 fits it with a little margin.
const double smallNativeTemplateHeight = 108;

const double mediumNativeTemplateHeight = 350;
