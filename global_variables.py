import random
import pygame
import numpy as np
import sys
pygame.font.init()

values = ("2","3","4","5","6","7","8","9","10","J","Q","K","A")
suits = ("❤️","♦️","♣️" ,"♠️")

value_index_dict = {
    "1": 1,
    "2": 2,
    "3": 3,
    "4": 4,
    "5": 5,
    "6": 6,
    "7": 7,
    "8": 8,
    "9": 9,
    "10": 10,
    "J": 11,
    "Q": 12,
    "K": 13,
    "A": 14
}

points_dict = {
    "Three of a kind" : [0, 2],
    "Straight"        : [2,4],
    "Flush"           : [4,8],
    "Full house"      : [6,12],
    "Four of a kind"  : [10,20],
    "Straight flush"  : [15,30],
    "Royal flush"     : [25,50]
}

points_dict_front = {
    "66": 1,
    "77": 2,
    "88": 3,
    "99": 4,
    "TT": 5,
    "JJ": 6,
    "QQ": 7,
    "KK": 8,
    "AA": 9,
    "222": 10,
    "333": 11,
    "444": 12,
    "555": 13,
    "666": 14,
    "777": 15,
    "888": 16,
    "999": 17,
    "TTT": 18,
    "JJJ": 19,
    "QQQ": 20,
    "KKK": 21,
    "AAA": 22
}

def flush(suits_list):
    if len(set(suits_list)) == 1:
        return True
    
    return False

def straight(values_list):
    values_list_copy = values_list.copy()
    if len(set(values_list)) < 5:
        return False
    if "A" in values_list_copy and "2" in values_list_copy:
        values_list_copy = ["1" if value == "A" else value for value in values_list_copy]
           
    index_array = np.array(sorted([value_index_dict[i] for i in values_list_copy]))
    if np.all(index_array[1:]-index_array[:-1] == np.ones(4)):
        return True
    
    return False

def straight_flush(suits_list, values_list):
    if flush(suits_list) and straight(values_list):
        return True
    
    return False

def royal_straight_flush(suits_list, values_list):
    if straight_flush(suits_list, values_list) and "A" in values_list and "K" in values_list:
        return True
    
    return False

def four_equal(values_list):
    values_list_copy = values_list.copy()
    values_set = set(values_list_copy)
    
    if len(values_set) == 2:
        for value in values_set:
            values_list_copy.remove(value)
        if len( set(values_list_copy)) == 1:
            
            return True
        
    return False

def full_house(values_list):
    values_list_copy = values_list.copy()
    values_set = set(values_list_copy)
    
    if len(values_set) == 2:
        for value in values_set:
            values_list_copy.remove(value)
        if len( set(values_list_copy)) == 2:
            return True
        
    return False

def three_equal(values_list):
    values_list_copy = values_list.copy()
    values_set = set(values_list_copy)
    
    if full_house(values_list) == False:
        
        for i in range(2):
            values_set = set(values_list_copy)
            
            for value in values_set:
                values_list_copy.remove(value)
                
        if len( set(values_list_copy)) == 1:
            return True
        
    return False

def two_pairs(values_list):
    values_list_copy = values_list.copy()
    values_set = set(values_list_copy)
    
    if len(values_set) == 3:
        for value in values_set:
            values_list_copy.remove(value)
        if len( set(values_list_copy)) == 2:
            return True
        
    return False

def one_pair(values_list):
    values_list_copy = values_list.copy()
    values_set = set(values_list_copy)
    
    if len(values_set) == 4:
        return True
    
    return False

def high_card(values_list):
    return np.array(sorted([value_index_dict[i] for i in values_list]))

def three_equal_front(values_list):
    if len(set(values_list)) == 1:
            return values_list[0]*3
        
    return False

def one_pair_front(values_list):
    values_list_copy = values_list.copy()
    values_set = set(values_list_copy)
    
    if len(values_set) == 2:
        for value in values_set:
            values_list_copy.remove(value)
        return values_list_copy[0]*2
    
    return False

def score(values_list, suits_list):
    hands = [
        royal_straight_flush(suits_list, values_list),
        straight_flush(suits_list, values_list),
        four_equal(values_list),
        full_house(values_list),
        flush(suits_list),
        straight(values_list),
        three_equal(values_list),
        two_pairs(values_list),
        one_pair(values_list),
        high_card(values_list)
    ]
    
    hands_str = [
        "Royal flush",
        "Straight flush",
        "Four of a kind",
        "Full house",
        "Flush",
        "Straight",
        "Three of a kind",
        "Two pairs",
        "One pair",
        "High card"
    ]

    for i in range(len(hands) - 1):
        if hands[i]:
            return hands_str[i]
    
    return "High card"

def score_front(values_list):
    hands = [
        three_equal_front(values_list),
        one_pair_front(values_list),
        high_card(values_list)
    ]
    
    hands_str = [
        "Three of a kind",
        "One pair",
        "High card"
    ]
    
    for i in range(len(hands) - 1):
        if hands[i]:
            return hands[i], hands_str[i]
    
    return "High card", "High card"