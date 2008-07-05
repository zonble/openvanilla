//
//  OVIMListController.m
//  OpenVanilla
//
//  Created by zonble on 2008/7/4.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "OVModulesListController.h"


@implementation OVModulesListController

- (void)awakeFromNib
{
	if (m_inputMethods == nil)
		m_inputMethods = [NSMutableArray new];
	if (m_ouputFilters == nil)
		m_ouputFilters = [NSMutableArray new];
	
	[u_outlineView setDelegate:self];
	[u_outlineView setDataSource:self];
}

- (void) dealloc
{
	[m_inputMethods release];
	[m_ouputFilters release];
	[super dealloc];
}


- (NSView *)view
{
	return u_mainView;
}
- (void)reload;
{
	[u_outlineView reloadData];
}

- (void)addInputMethod:(id)inputMethod
{
	if (m_inputMethods == nil) {
		m_inputMethods = [NSMutableArray new];
	}
	[m_inputMethods addObject:inputMethod];
}
- (void)addOutputFilter:(id)outputFilter
{
	if (m_ouputFilters == nil) {
		m_ouputFilters = [NSMutableArray new];
	}	
	[m_ouputFilters addObject:outputFilter];
}


- (void)switchToView: (NSView *)view
{
	if ([[u_settingView subviews] count]) {
		[[[u_settingView subviews] objectAtIndex:0] removeFromSuperview];
	}
	if (view) {
		NSRect frame = [view frame];
//		frame.origin.y = [u_settingView frame].size.height - frame.size.height;
		frame.size.height = [u_settingView frame].size.height;
		frame.size.width = [u_settingView frame].size.width;
		[view setFrame:frame];
		[u_settingView addSubview:view];
	}
}


#pragma mark outlineView delegate methods.

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (item == nil) {
		return 2;
	}	
	else if (item == m_inputMethods) {
		return [m_inputMethods count];
	}
	else if (item == m_ouputFilters) {
		return [m_ouputFilters count];
	}
	return 0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(id)item
{
	return YES;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	if (item == nil || item == m_inputMethods || item == m_ouputFilters) {
		return YES;
	}
	return NO;
}

- (id)outlineView:(NSOutlineView *)outlineView
			child:(int)index
		   ofItem:(id)item
{
	if (item == nil) {
		if (index == 0) {
			return m_inputMethods;
		}
		else if (index == 1) {
			return m_ouputFilters;
		}
	}
	else if (item == m_inputMethods) {
		return [m_inputMethods objectAtIndex:index];
	}
	else if (item == m_ouputFilters) {
		return [m_ouputFilters objectAtIndex:index];
	}
	
	
	return nil;
}

- (NSCell *)textField: (NSString *) text
{
	NSCell *cell = [[[NSCell alloc] initTextCell:text] autorelease];
	return cell;
}

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	if ([[tableColumn identifier] isEqualToString:@"enabled"]) {
		if (item == nil || item == m_inputMethods || item == m_ouputFilters) {
			return [self textField:@" "];
		}
	}
	return [tableColumn dataCell];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	if ([[tableColumn identifier] isEqualToString:@"localizedName"]) {
		if (item == nil) {
			return @"/";
		}
		else if (item == m_inputMethods) {
			return @"Input Methods";
		}
		else if (item == m_ouputFilters) {
			return @"Output Filters";
		}
		else {			
			return [item localizedName];;
		}
	}
	else if ([[tableColumn identifier] isEqualToString:@"enabled"]) {
		if (item == nil || item == m_inputMethods || item == m_ouputFilters) {
			return nil;
		}
		return [NSNumber numberWithBool:YES];		
	}
	return nil;
}

- (void)setCurrentItem:(id)item
{
	id tmp = _currentItem;
	_currentItem = [item retain];
	[tmp release];	
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	if (item == nil || item == m_inputMethods || item == m_ouputFilters) {
		return NO;
	}
	[self setCurrentItem:item];
	return YES;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	//NSLog([notification description]);
//	NSLog(@"Changes");
//	NSLog([_currentItem description]);
//	NSLog([[_currentItem view] description]);
	[self switchToView:[_currentItem view]];
}

@end
