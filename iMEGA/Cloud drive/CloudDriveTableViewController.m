/**
 * @file CloudDriveTableViewController.m
 * @brief Cloud drive table view controller of the app.
 *
 * (c) 2013-2014 by Mega Limited, Auckland, New Zealand
 *
 * This file is part of the MEGA SDK - Client Access Engine.
 *
 * Applications using the MEGA API must present a valid application key
 * and comply with the the rules set forth in the Terms of Service.
 *
 * The MEGA SDK is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 *
 * @copyright Simplified (2-clause) BSD License.
 *
 * You should have received a copy of the license along with this
 * program.
 */

#import "CloudDriveTableViewController.h"
#import "NodeTableViewCell.h"
#import "SVProgressHUD.h"
#import "LoginViewController.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import "DetailsNodeInfoViewController.h"
#import "Helper.h"
#import "MEGAPreview.h"
#import "MoveCopyNodeViewController.h"

@interface CloudDriveTableViewController () {
    UIAlertView *folderAlertView;
    UIAlertView *removeAlertView;
    
    NSInteger indexNodeSelected;
    NSUInteger remainingOperations;
    
    NSMutableArray *exportLinks;
    
    NSMutableArray *matchSearchNodes;
}

@property (weak, nonatomic) IBOutlet UIBarButtonItem *addBarButtonItem;

@property (weak, nonatomic) IBOutlet UIView *headerView;
@property (weak, nonatomic) IBOutlet UILabel *filesFolderLabel;

@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *shareBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *moveBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *deleteBarButtonItem;

@property (nonatomic, strong) MEGANodeList *nodes;

@property (nonatomic, strong) NSMutableArray *cloudImages;
@property (nonatomic, strong) NSMutableArray *selectedNodesArray;

@property (nonatomic) UIImagePickerController *imagePickerController;

@end

@implementation CloudDriveTableViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSArray *buttonsItems = @[self.editButtonItem, self.addBarButtonItem];
    self.navigationItem.rightBarButtonItems = buttonsItems;
    
    NSString *thumbsDirectory = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"thumbs"];
    NSError *error;
    if (![[NSFileManager defaultManager] fileExistsAtPath:thumbsDirectory]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:thumbsDirectory withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Create directory error: %@", error);
        }
    }
    
    NSString *previewsDirectory = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"previews"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:previewsDirectory]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:previewsDirectory withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Create directory error: %@", error);
        }
    }
    
    [self.searchDisplayController.searchResultsTableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [[MEGASdkManager sharedMEGASdk] addMEGADelegate:self];
    [[MEGASdkManager sharedMEGASdk] retryPendingConnections];
    [self reloadUI];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    if (self.tableView.isEditing) {
        self.selectedNodesArray = nil;
        [self setEditing:NO animated:NO];
    }
    
    [[MEGASdkManager sharedMEGASdk] removeMEGADelegate:self];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.searchDisplayController.searchResultsTableView) {
        return [matchSearchNodes count];
    } else {
        return [[self.nodes size] integerValue];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"nodeCell";
    
    NodeTableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier forIndexPath:indexPath];
    
    if (cell == nil) {
        cell = [[NodeTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    
    MEGANode *node = nil;
    
    if (tableView == self.searchDisplayController.searchResultsTableView) {
        node = [matchSearchNodes objectAtIndex:indexPath.row];
    } else {
        node = [self.nodes nodeAtIndex:indexPath.row];
    }
    
    NSString *thumbnailFilePath = [Helper pathForNode:node searchPath:NSCachesDirectory directory:@"thumbs"];
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:thumbnailFilePath];
    
    if (!fileExists && [node hasThumbnail]) {
        [[MEGASdkManager sharedMEGASdk] getThumbnailNode:node destinationFilePath:thumbnailFilePath];
    }
    
    if (!fileExists) {
        [cell.thumbnailImageView setImage:[Helper imageForNode:node]];
    } else {
        [cell.thumbnailImageView setImage:[UIImage imageWithContentsOfFile:thumbnailFilePath]];
    }
    
    cell.nameLabel.text = [node name];
    
    if ([node type] == MEGANodeTypeFile) {
        struct tm *timeinfo;
        char buffer[80];
        
        time_t rawtime = [[node modificationTime] timeIntervalSince1970];
        timeinfo = localtime(&rawtime);
        
        strftime(buffer, 80, "%d/%m/%y %H:%M", timeinfo);
        
        NSString *date = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
        NSString *size = [NSByteCountFormatter stringFromByteCount:node.size.longLongValue  countStyle:NSByteCountFormatterCountStyleMemory];
        NSString *sizeAndDate = [NSString stringWithFormat:@"%@ • %@", size, date];
        
        cell.infoLabel.text = sizeAndDate;
    } else {
        NSInteger files = [[MEGASdkManager sharedMEGASdk] numberChildFilesForParent:node];
        NSInteger folders = [[MEGASdkManager sharedMEGASdk] numberChildFoldersForParent:node];
        
        NSString *filesAndFolders;
        
        if (files == 0 || files > 1) {
            if (folders == 0 || folders > 1) {
                filesAndFolders = [NSString stringWithFormat:NSLocalizedString(@"foldersFiles", @"Folders, files"), (int)folders, (int)files];
            } else if (folders == 1) {
                filesAndFolders = [NSString stringWithFormat:NSLocalizedString(@"folderFiles", @"Folder, files"), (int)folders, (int)files];
            }
        } else if (files == 1) {
            if (folders == 0 || folders > 1) {
                filesAndFolders = [NSString stringWithFormat:NSLocalizedString(@"foldersFile", @"Folders, file"), (int)folders, (int)files];
            } else if (folders == 1) {
                filesAndFolders = [NSString stringWithFormat:NSLocalizedString(@"folderFile", @"Folders, file"), (int)folders, (int)files];
            }
        }
        
        cell.infoLabel.text = filesAndFolders;
    }
    
    cell.nodeHandle = [node handle];
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

//- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
//    return self.headerView;
//}
//
//- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
//    return 20.0;
//}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    MEGANode *node = nil;
    
    if (tableView == self.searchDisplayController.searchResultsTableView) {
        node = [matchSearchNodes objectAtIndex:indexPath.row];
    } else {
        node = [self.nodes nodeAtIndex:indexPath.row];
    }
    
    if (tableView.isEditing) {
        [self.selectedNodesArray addObject:node];
        
        [self.shareBarButtonItem setEnabled:YES];
        [self.moveBarButtonItem setEnabled:YES];
        [self.deleteBarButtonItem setEnabled:YES];
        
        return;
    }
    
    switch ([node type]) {
        case MEGANodeTypeFolder: {
            CloudDriveTableViewController *cdvc = [self.storyboard instantiateViewControllerWithIdentifier:@"CloudDriveID"];
            [cdvc setParentNode:node];
            [self.navigationController pushViewController:cdvc animated:YES];
            break;
        }
            
        case MEGANodeTypeFile: {
            NSString *name = [node name];
            if (isImage(name.lowercaseString.pathExtension)) {
                
                int offsetIndex = 0;
                self.cloudImages = [NSMutableArray new];
                
                if (tableView == self.searchDisplayController.searchResultsTableView) {
                    for (NSInteger i = 0; i < matchSearchNodes.count; i++) {
                        MEGANode *n = [matchSearchNodes objectAtIndex:i];
                        
                        if (isImage([n name].lowercaseString.pathExtension)) {
                            MEGAPreview *photo = [MEGAPreview photoWithNode:n];
                            photo.caption = [n name];
                            [self.cloudImages addObject:photo];
                            if ([n handle] == [node handle]) {
                                offsetIndex = (int)[self.cloudImages count] - 1;
                            }
                        }
                    }
                } else {
                    for (NSInteger i = 0; i < [[self.nodes size] integerValue]; i++) {
                        MEGANode *n = [self.nodes nodeAtIndex:i];
                        
                        if (isImage([n name].lowercaseString.pathExtension)) {
                            MEGAPreview *photo = [MEGAPreview photoWithNode:n];
                            photo.caption = [n name];
                            [self.cloudImages addObject:photo];
                            if ([n handle] == [node handle]) {
                                offsetIndex = (int)[self.cloudImages count] - 1;
                            }
                        }
                    }
                }
                
                MWPhotoBrowser *browser = [[MWPhotoBrowser alloc] initWithDelegate:self];
                
                browser.displayActionButton = YES;
                browser.displayNavArrows = YES;
                browser.displaySelectionButtons = NO;
                browser.zoomPhotosToFill = YES;
                browser.alwaysShowControls = NO;
                browser.enableGrid = YES;
                browser.startOnGrid = NO;
                
                // Optionally set the current visible photo before displaying
                //    [browser setCurrentPhotoIndex:1];
                
                [self.navigationController pushViewController:browser animated:YES];
                
                [browser showNextPhotoAnimated:YES];
                [browser showPreviousPhotoAnimated:YES];
                [browser setCurrentPhotoIndex:offsetIndex];
            }
            break;
        }
            
        default:
            break;
    }
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    MEGANode *node = [self.nodes nodeAtIndex:indexPath.row];
    
    if (tableView.isEditing) {
        
        //tempArray avoid crash: "was mutated while being enumerated."
        NSMutableArray *tempArray = [self.selectedNodesArray copy];
        for (MEGANode *n in tempArray) {
            if (n.handle == node.handle) {
                [self.selectedNodesArray removeObject:n];
            }
        }
        
        if (self.selectedNodesArray.count == 0) {
            [self.shareBarButtonItem setEnabled:NO];
            [self.moveBarButtonItem setEnabled:NO];
            [self.deleteBarButtonItem setEnabled:NO];
        }
        
        return;
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    MEGANode *node = nil;
    
    if (tableView == self.searchDisplayController.searchResultsTableView) {
        node = [matchSearchNodes objectAtIndex:indexPath.row];
    } else {
        node = [self.nodes nodeAtIndex:indexPath.row];
    }
    
    DetailsNodeInfoViewController *nodeInfoDetailsVC = [self.storyboard instantiateViewControllerWithIdentifier:@"nodeInfoDetails"];
    [nodeInfoDetailsVC setNode:node];
    [self.navigationController pushViewController:nodeInfoDetailsVC animated:YES];
}


- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    MEGANode *n = [self.nodes nodeAtIndex:indexPath.row];
    
    self.selectedNodesArray = [NSMutableArray new];
    [self.selectedNodesArray addObject:n];
    
    [self.shareBarButtonItem setEnabled:YES];
    [self.moveBarButtonItem setEnabled:YES];
    [self.deleteBarButtonItem setEnabled:YES];
    return (UITableViewCellEditingStyleDelete);
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle==UITableViewCellEditingStyleDelete) {
        MEGANode *node = [self.nodes nodeAtIndex:indexPath.row];
        remainingOperations = 1;
        [[MEGASdkManager sharedMEGASdk] moveNode:node newParent:[[MEGASdkManager sharedMEGASdk] rubbishNode]];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (([[[UIDevice currentDevice] systemVersion] compare:@"8.0" options:NSNumericSearch] == NSOrderedAscending)) {
        return 44.0;
    }
    else {
        return UITableViewAutomaticDimension;
    }
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (([[[UIDevice currentDevice] systemVersion] compare:@"8.0" options:NSNumericSearch] == NSOrderedAscending)) {
        return 44.0;
    }
    else {
        return UITableViewAutomaticDimension;
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    
    if (editing) {
        [self.addBarButtonItem setEnabled:NO];
        [self.navigationItem.leftBarButtonItems.firstObject setEnabled:NO];
    } else {
        self.selectedNodesArray = nil;
        [self.addBarButtonItem setEnabled:YES];
    }
    
    if (!self.selectedNodesArray) {
        self.selectedNodesArray = [NSMutableArray new];
        [self.shareBarButtonItem setEnabled:NO];
        [self.moveBarButtonItem setEnabled:NO];
        [self.deleteBarButtonItem setEnabled:NO];
    }
    
    [self.tabBarController.tabBar addSubview:self.toolbar];
    
    [UIView animateWithDuration:animated ? .33 : 0 animations:^{
        self.toolbar.frame = CGRectMake(0, editing ? 0 : 49 , CGRectGetWidth(self.view.frame), 49);
    }];
    
}

#pragma mark - MWPhotoBrowserDelegate

- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser {
    return self.cloudImages.count;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < self.cloudImages.count) {
        return [self.cloudImages objectAtIndex:index];
    }
    
    return nil;
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 0) {
        folderAlertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"newFolderTitle", @"Create new folder") message:NSLocalizedString(@"newFolderMessage", @"Name for the new folder") delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", @"Cancel") otherButtonTitles:NSLocalizedString(@"createFolderButton", @"Create"), nil];
        [folderAlertView setAlertViewStyle:UIAlertViewStylePlainTextInput];
        [folderAlertView textFieldAtIndex:0].text = @"";
        folderAlertView.tag = 1;
        [folderAlertView show];
    } else if (buttonIndex == 1) {
        [self showImagePickerForSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
    }
}

#pragma mark - UIAlertDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 1) {
        if (buttonIndex == 1) {
            [[MEGASdkManager sharedMEGASdk] createFolderWithName:[[folderAlertView textFieldAtIndex:0] text] parent:self.parentNode];
        }
    }
    
    if (alertView.tag == 2) {
        if (buttonIndex == 1) {
            remainingOperations = self.selectedNodesArray.count;
            for (NSInteger i = 0; i < self.selectedNodesArray.count; i++) {
                [[MEGASdkManager sharedMEGASdk] moveNode:[self.selectedNodesArray objectAtIndex:i] newParent:[[MEGASdkManager sharedMEGASdk] rubbishNode]];
            }
        }
    }
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    NSURL *assetURL = [info objectForKey:UIImagePickerControllerReferenceURL];
    
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    [library assetForURL:assetURL resultBlock:^(ALAsset *asset)  {
        NSString *name = asset.defaultRepresentation.filename;
        NSDate *modificationTime = [asset valueForProperty:ALAssetPropertyDate];
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.image= [info objectForKey:@"UIImagePickerControllerOriginalImage"];
        NSData *webData = UIImageJPEGRepresentation(imageView.image, 0.9);
        
        
        NSString *localFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        [webData writeToFile:localFilePath atomically:YES];
        
        NSError *error = nil;
        NSDictionary *attributesDictionary = [NSDictionary dictionaryWithObject:modificationTime forKey:NSFileModificationDate];
        [[NSFileManager defaultManager] setAttributes:attributesDictionary ofItemAtPath:localFilePath error:&error];
        if (error) {
            NSLog(@"Error change modification date of file %@", error);
        }
        
        [[MEGASdkManager sharedMEGASdk] startUploadWithLocalPath:localFilePath parent:self.parentNode];
    } failureBlock:nil];
    
    [self dismissViewControllerAnimated:YES completion:NULL];
    self.imagePickerController = nil;
}


- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissViewControllerAnimated:YES completion:NULL];
}

#pragma mark - Private methods

- (void)reloadUI {
    NSString *filesAndFolders;
    
    if (!self.parentNode) {
        self.parentNode = [[MEGASdkManager sharedMEGASdk] rootNode];
    }
    if ([[self.parentNode name] isEqualToString:@"CRYPTO_ERROR"]) {
        [self.navigationItem setTitle:NSLocalizedString(@"cloudDrive", @"Cloud drive")];
    } else {
        [self.navigationItem setTitle:[self.parentNode name]];
    }
    
    self.nodes = [[MEGASdkManager sharedMEGASdk] childrenForParent:self.parentNode];
    
    NSInteger files = [[MEGASdkManager sharedMEGASdk] numberChildFilesForParent:self.parentNode];
    NSInteger folders = [[MEGASdkManager sharedMEGASdk] numberChildFoldersForParent:self.parentNode];
    
    if (files == 0 || files > 1) {
        if (folders == 0 || folders > 1) {
            filesAndFolders = [NSString stringWithFormat:NSLocalizedString(@"foldersFiles", @"Folders, files"), (int)folders, (int)files];
        } else if (folders == 1) {
            filesAndFolders = [NSString stringWithFormat:NSLocalizedString(@"folderFiles", @"Folder, files"), (int)folders, (int)files];
        }
    } else if (files == 1) {
        if (folders == 0 || folders > 1) {
            filesAndFolders = [NSString stringWithFormat:NSLocalizedString(@"foldersFile", @"Folders, file"), (int)folders, (int)files];
        } else if (folders == 1) {
            filesAndFolders = [NSString stringWithFormat:NSLocalizedString(@"folderFile", @"Folders, file"), (int)folders, (int)files];
        }
    }
    
    self.filesFolderLabel.text = filesAndFolders;
    
    [self.tableView reloadData];
}

- (void)showImagePickerForSourceType:(UIImagePickerControllerSourceType)sourceType {
    
    UIImagePickerController *imagePickerController = [[UIImagePickerController alloc] init];
    imagePickerController.modalPresentationStyle = UIModalPresentationCurrentContext;
    imagePickerController.sourceType = sourceType;
    imagePickerController.delegate = self;
    
    self.imagePickerController = imagePickerController;
    [self.tabBarController presentViewController:self.imagePickerController animated:YES completion:nil];
}

#pragma mark - IBActions

- (IBAction)optionAdd:(id)sender {
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil
                                                             delegate:self
                                                    cancelButtonTitle:NSLocalizedString(@"cancel", @"Cancel")
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:NSLocalizedString(@"createFolder", @"Create folder"), NSLocalizedString(@"uploadPhoto", @"Upload photo"), nil];
    [actionSheet showFromTabBar:self.tabBarController.tabBar];
}

- (IBAction)shareLinkAction:(UIBarButtonItem *)sender {
    exportLinks = [NSMutableArray new];
    remainingOperations = self.selectedNodesArray.count;
    
    for (MEGANode *n in self.selectedNodesArray) {
        [[MEGASdkManager sharedMEGASdk] exportNode:n];
    }
}

- (IBAction)moveCopyAction:(UIBarButtonItem *)sender {
    UINavigationController *mcnc = [self.storyboard instantiateViewControllerWithIdentifier:@"moveNodeNav"];
    [self presentViewController:mcnc animated:YES completion:nil];
    
    MoveCopyNodeViewController *mcnvc = mcnc.viewControllers.firstObject;
    mcnvc.parentNode = [[MEGASdkManager sharedMEGASdk] rootNode];
    mcnvc.moveOrCopyNodes = [NSArray arrayWithArray:self.selectedNodesArray];
}

- (IBAction)deleteAction:(UIBarButtonItem *)sender {
    NSString *message = (self.selectedNodesArray.count > 1) ? [NSString stringWithFormat:NSLocalizedString(@"moveMultipleNodesToRubbishBinMessage", nil), self.selectedNodesArray.count] :[NSString stringWithString:NSLocalizedString(@"moveNodeToRubbishBinMessage", nil)];
    
    removeAlertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"moveNodeToRubbishBinTitle", @"Remove node") message:message delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", @"Cancel") otherButtonTitles:NSLocalizedString(@"ok", @"OK"), nil];
    [removeAlertView show];
    removeAlertView.tag = 2;
    [removeAlertView show];
}

#pragma mark - Content Filtering

- (void)filterContentForSearchText:(NSString*)searchText scope:(NSString*)scope {
    
    matchSearchNodes = [NSMutableArray new];
    MEGANodeList *allNodeList = nil;
    
    if([scope isEqualToString:@"Recursive"]) {
        allNodeList = [[MEGASdkManager sharedMEGASdk] nodeListSearchForNode:self.parentNode searchString:searchText recursive:YES];
    } else {
        allNodeList = [[MEGASdkManager sharedMEGASdk] nodeListSearchForNode:self.parentNode searchString:searchText recursive:NO];
    }
    
    for (NSInteger i = 0; i < [allNodeList.size integerValue]; i++) {
        MEGANode *n = [allNodeList nodeAtIndex:i];
        [matchSearchNodes addObject:n];
    }
    
}

#pragma mark - UISearchDisplayControllerDelegate

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)searchString {
    [self filterContentForSearchText:searchString scope:
     [[self.searchDisplayController.searchBar scopeButtonTitles] objectAtIndex:[self.searchDisplayController.searchBar selectedScopeButtonIndex]]];
    
    return YES;
}

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchScope:(NSInteger)searchOption {
    [self filterContentForSearchText:self.searchDisplayController.searchBar.text scope:
     [[self.searchDisplayController.searchBar scopeButtonTitles] objectAtIndex:searchOption]];
    
    return YES;
}

#pragma mark - MEGARequestDelegate

- (void)onRequestStart:(MEGASdk *)api request:(MEGARequest *)request {
    switch ([request type]) {
        case MEGARequestTypeExport:
            [SVProgressHUD showWithStatus:NSLocalizedString(@"generateLink", @"Generate link...")];
            break;
            
        default:
            break;
    }
}

- (void)onRequestFinish:(MEGASdk *)api request:(MEGARequest *)request error:(MEGAError *)error {
    if ([error type]) {
        return;
    }
    
    switch ([request type]) {
        case MEGARequestTypeFetchNodes:
            [SVProgressHUD dismiss];
            break;
            
        case MEGARequestTypeGetAttrFile: {
            for (NodeTableViewCell *ntvc in [self.tableView visibleCells]) {
                if ([request nodeHandle] == [ntvc nodeHandle]) {
                    MEGANode *node = [[MEGASdkManager sharedMEGASdk] nodeForHandle:[request nodeHandle]];
                    NSString *thumbnailFilePath = [Helper pathForNode:node searchPath:NSCachesDirectory directory:@"thumbs"];
                    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:thumbnailFilePath];
                    if (fileExists) {
                        [ntvc.thumbnailImageView setImage:[UIImage imageWithContentsOfFile:thumbnailFilePath]];
                    }
                }
            }
            
            for (NodeTableViewCell *ntvc in [self.searchDisplayController.searchResultsTableView visibleCells]) {
                if ([request nodeHandle] == [ntvc nodeHandle]) {
                    MEGANode *node = [[MEGASdkManager sharedMEGASdk] nodeForHandle:[request nodeHandle]];
                    NSString *thumbnailFilePath = [Helper pathForNode:node searchPath:NSCachesDirectory directory:@"thumbs"];
                    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:thumbnailFilePath];
                    if (fileExists) {
                        [ntvc.thumbnailImageView setImage:[UIImage imageWithContentsOfFile:thumbnailFilePath]];
                    }
                }
            }
            
            break;
        }
            
        case MEGARequestTypeMove: {
            remainingOperations--;
            if (remainingOperations == 0) {
                NSString *message = (self.selectedNodesArray.count <= 1 ) ? [NSString stringWithFormat:NSLocalizedString(@"fileMovedToRubbishBin", nil)] : [NSString stringWithFormat:NSLocalizedString(@"filesMovedToRubbishBin", nil), self.selectedNodesArray.count];
                [SVProgressHUD showSuccessWithStatus:message];
                [self setEditing:NO animated:NO];
            }
            break;
        }
            
        case MEGARequestTypeExport: {
            remainingOperations--;
            
            MEGANode *n = [[MEGASdkManager sharedMEGASdk] nodeForHandle:request.nodeHandle];
            
            NSString *name = [NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"fileName", nil), n.name];
            
            NSString *size = [NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"fileSize", nil), n.isFile ? [NSByteCountFormatter stringFromByteCount:[[n size] longLongValue]  countStyle:NSByteCountFormatterCountStyleMemory] : NSLocalizedString(@"folder", nil)];
            
            NSString *link = [request link];
            
            NSArray *tempArray = [NSArray arrayWithObjects:[NSString stringWithFormat:@"%@ \n %@ \n %@\n", name, size, link], nil];
            [exportLinks addObjectsFromArray:tempArray];
            
            if (remainingOperations == 0) {
                [SVProgressHUD dismiss];
                UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:exportLinks applicationActivities:nil];
                activityVC.excludedActivityTypes = @[UIActivityTypePrint, UIActivityTypeCopyToPasteboard, UIActivityTypeAssignToContact, UIActivityTypeSaveToCameraRoll];
                [self presentViewController:activityVC animated:YES completion:nil ];
                [self setEditing:NO animated:NO];
            }
            break;
        }
            
        default:
            break;
    }
}

- (void)onRequestTemporaryError:(MEGASdk *)api request:(MEGARequest *)request error:(MEGAError *)error {
}

#pragma mark - MEGAGlobalDelegate

- (void)onReloadNeeded:(MEGASdk *)api {
}

- (void)onNodesUpdate:(MEGASdk *)api nodeList:(MEGANodeList *)nodeList {
    [self reloadUI];
}


#pragma mark - MEGATransferDelegate

- (void)onTransferStart:(MEGASdk *)api transfer:(MEGATransfer *)transfer {
}

- (void)onTransferUpdate:(MEGASdk *)api transfer:(MEGATransfer *)transfer {
}

- (void)onTransferFinish:(MEGASdk *)api transfer:(MEGATransfer *)transfer error:(MEGAError *)error {
    if ([transfer type] == MEGATransferTypeUpload) {
        NSError *e = nil;
        NSString *localFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[transfer fileName]];
        BOOL success = [[NSFileManager defaultManager] removeItemAtPath:localFilePath error:&e];
        if (!success || e) {
            NSLog(@"remove file error %@", e);
        }
    }
}

-(void)onTransferTemporaryError:(MEGASdk *)api transfer:(MEGATransfer *)transfer error:(MEGAError *)error {
}

@end