// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./DateTime.sol";


contract VIPCard is ERC721, ERC721Burnable, Ownable, DateTime{
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter; 
    
    AggregatorV3Interface internal priceFeed; // Gets current price of ETH
    //priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331); Won't work on test network.


    //TOKEN MINTING VARIABLES
    uint256 mintingFee = 1 ether;
    //END TOKEN MINTING VARIABLES
    
    
    //ETH PAY VARIABLES
    int256 discountPercent = 10;
    int256[10] public tokenIdToDebt;
    //END ETH PAY VARIABLES
    
    
    //SONG REQUEST VARIABLES
    uint8 songQueueSize = 20;
    string[20] public songQueue; //Holds songs requested
    uint8 queueEnd = 0;
    uint8 nextSong = 0;
    //END SONG REQUEST VARIABLES 
    
    //KING BOOTH AUCTION VARIABLES
    address public highestBidder;
    uint256 public highestBid;
    mapping(address => uint256) pendingReturns;
    bool active;
    event HighestBidIncreased(address bidder, uint amount);
    event AuctionEnded(address winner, uint amount);
    event AuctionStarted();
    error AuctionAlreadyEnded();
    error AuctionAlreadyStarted();
    error BidNotHighEnough(uint highestBid);
    //END KING BOOTH AUCTION VARIABLES
    
    
    constructor() ERC721("The Club VIP Card", "TCVC") {}

    function _baseURI() internal pure override returns (string memory) {
        return "https:\\\\theclub.rs";
    }

    function requestSong(string memory songName) public onlyTokenHolder {
        require( ((queueEnd+1) % songQueueSize) != nextSong , "Song request queue is full.");
        songQueue[queueEnd] = songName;
        queueEnd = (queueEnd+1) % songQueueSize;
        
    }
    
    function playSong() public onlyOwner returns (string memory)  {
        string memory currentSong = songQueue[nextSong];
        nextSong = (nextSong+1) % songQueueSize;
        return currentSong;
        
    }
    
    function getNextSong() public view returns (uint8) {
        return nextSong;
    }
    
    function getSongAtPosition(uint8 index) public view returns (string memory){
        return songQueue[index % songQueueSize];
    }
    
    function getSongQueueStartAndEnd() public view returns (uint8, uint8){
        return (nextSong, queueEnd);
    }
    
    function bid() public payable onlyTokenHolder{
        uint8 day = getWeekday(block.timestamp);
        if (day != 4){
            revert AuctionAlreadyEnded();
        }
        if (!active){
            revert AuctionAlreadyEnded();
        }
        if (msg.value < highestBid){
            revert BidNotHighEnough(highestBid);
        }
        if (highestBid != 0){
            pendingReturns[highestBidder] += highestBid;
        }
        highestBidder = msg.sender;
        highestBid = msg.value;
        emit HighestBidIncreased(msg.sender, msg.value);
    }
    
    function withdraw() public returns (bool) {
        uint amount = pendingReturns[msg.sender];
        if (amount > 0) {
            pendingReturns[msg.sender] = 0;
            if (!payable(msg.sender).send(amount)) {
                pendingReturns[msg.sender] = amount;
                return false;
            }
        }
        return true;
    }
    
    function auctionEnd() public onlyOwner{
        
        if (!active)
            revert AuctionAlreadyEnded();

        active = false;
        emit AuctionEnded(highestBidder, highestBid);
    }
    
    function auctionStart() public onlyOwner {
        if (active)
            revert AuctionAlreadyStarted();

        active = true;
        highestBid = 0;
        highestBidder = address(0);
        emit HighestBidIncreased(highestBidder, highestBid);
        emit AuctionStarted();
    }
    

    modifier onlyTokenHolder{
        require(balanceOf(msg.sender) > 0, "You must be a token holder to use this service."); 
        _;
    }
    


    function safeMint() public payable {
        require(_tokenIdCounter.current() < 10, "Only 10 vip cards can exist.");
        require(msg.value >= mintingFee, "Insufficient funds.");
        require(balanceOf(msg.sender) == 0, "One address can only hold one token.");
        
        _safeMint(msg.sender, _tokenIdCounter.current());
        _tokenIdCounter.increment();
        
    }
    
    function setDebt(int _priceInRSD, uint256 _tokenId) public onlyOwner {
        require(_priceInRSD > 0, "Debt can't be negative or 0.");
        require(_tokenId < _tokenIdCounter.current(), "Token does not exist.");
        int256 oldDebt = tokenIdToDebt[_tokenId];
        int256 priceInWei = getLatestPrice1RSDtoWEI() * _priceInRSD;
        int256 priceWithDiscount = priceInWei - (priceInWei/100 * discountPercent);
        int256 newDebt = oldDebt - priceWithDiscount;
        require(newDebt < oldDebt, "Overflow protection triggered.");
        tokenIdToDebt[_tokenId] = newDebt;
    }
    
    function getDebt(uint256 _tokenId) public view returns (int256){
        return tokenIdToDebt[_tokenId];
    }
    
    function payDebt(uint256 _tokenId) public payable{
        require(msg.value > 0, "You have to send SOME repayment amount.");
        require(tokenIdToDebt[_tokenId] < 0, "Token is not in debt.");
        int256 oldDebt = tokenIdToDebt[_tokenId];
        int256 newDebt = oldDebt + int256(msg.value); //verovatno opasno
        require(newDebt > oldDebt, "Overflow protection triggered.");
        tokenIdToDebt[_tokenId] = newDebt;
    }
    
    function getLatestPrice() private pure returns (int) {
        // "pure" would be "view" in a real enviroment.
        /*
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        */
        int price = 312530; //Price of 1ETH in RSD (rounded down for the convenience of our customers :) 
        return price;
    }
    
    function getLatestPrice1RSDtoWEI() public pure returns (int){
        //10**18 wei = 1 ETH = 312530 RSD
        int ETHinRSD = getLatestPrice();
        int RSDtoWEI = (10**18/ETHinRSD);
        return RSDtoWEI;
        
    }
}
