// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./marketplace.sol";

contract KajalMarketplace is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    DataStructure
{
    uint256 public platformFee;
    address public platformFeeAddress;

    enum ListingType {
        Sale,
        Auction,
        Stacking
    }

    enum Expiration {
        months_noExpiration,
        months_3,
        months_6,
        months_9,
        months_12
    }

    struct nftData {
        uint256 nftId;
        address nftIdCollectionAddress;
        address currency;
        uint256 reservePricePerToken;
        uint256 buyoutPricePerToken;
        uint256 startTime;
        uint256 endTime;
        ListingType nftListingType;
        Expiration expiration;
    }

    struct listedNftData {
        uint256 nftId;
        address payable nftOwner;
        address nftIdCollectionAddress;
        address currency;
        uint256 reservePricePerToken;
        uint256 buyoutPricePerToken;
        uint256 startTime;
        uint256 endTime;
        ListingType nftListingType;
        Expiration expiration;
        bool isMarketPlace;
    }

    mapping(address => mapping(uint256 => listedNftData))
        public nftDatasetAddress;

    struct bidderInfo {
        uint256 highBid;
        address payable higherBidder;
        uint256 index;
        address[] bidderAddress;
        uint256[] bidAmount;
    }
    mapping(address => mapping(uint256 => bidderInfo)) public biddingInfo;

    struct buyerInfo {
        bool isBidder;
        uint256 amount;
        uint256 index;
    }
    mapping(address => mapping(uint256 => mapping(address => buyerInfo)))
        public BuyerInfo;

    struct stackingInfo {
        bool isStacked;
        uint256 stackTime;
        uint256 completeTime;
        address currency;
        uint256 reward;
    }
    mapping(address => mapping(uint256 => mapping(address => stackingInfo)))
        public StackingInfo;

    struct stacking {
        address currency;
        uint256 reward_3;
        uint256 reward_6;
        uint256 reward_9;
        uint256 reward_12;
    }
    stacking public Stacking;

    modifier onlyNftOwner(address nftCollectionAddress, uint256 nftId) {
        require(
            msg.sender ==
                nftDatasetAddress[nftCollectionAddress][nftId].nftOwner,
            "You are not the owner of this nft."
        );
        _;
    }

    modifier onMarketPlace(address nftCollectionAddress, uint256 nftId) {
        require(
            nftDatasetAddress[nftCollectionAddress][nftId].isMarketPlace,
            "This nft is not listed on this market place yet."
        );
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _platformFee,
        address _platformFeeAddress,
        stacking memory stackInfo
    ) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        platformFee = _platformFee;
        platformFeeAddress = _platformFeeAddress;

        require(
            stackInfo.reward_3 < stackInfo.reward_6 &&
                stackInfo.reward_6 < stackInfo.reward_9 &&
                stackInfo.reward_9 < stackInfo.reward_12,
            "Please put reward correctly"
        );

        Stacking.currency = stackInfo.currency;
        Stacking.reward_3 = stackInfo.reward_3;
        Stacking.reward_6 = stackInfo.reward_6;
        Stacking.reward_9 = stackInfo.reward_9;
        Stacking.reward_12 = stackInfo.reward_12;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    //----------------------------Functions only MarketPalace Owner can call --------------------------

    //MarketPlace Owner can update the platformFee and platformFeeAddress
    function updatePlatformFeeAndAddress(
        uint256 _platformFee,
        address _platformFeeAddress
    ) public onlyOwner returns (bool) {
        platformFee = _platformFee;
        platformFeeAddress = _platformFeeAddress;

        return true;
    }

    //MarketPlace Owner can update the stacking reward and its currency address
    function updateStackingRewardAndAddress(stacking memory stackInfo)
        public
        onlyOwner
        returns (bool)
    {
        require(
            stackInfo.reward_3 < stackInfo.reward_6 &&
                stackInfo.reward_6 < stackInfo.reward_9 &&
                stackInfo.reward_9 < stackInfo.reward_12,
            "Please put reward correctly"
        );

        Stacking.currency = stackInfo.currency;
        Stacking.reward_3 = stackInfo.reward_3;
        Stacking.reward_6 = stackInfo.reward_6;
        Stacking.reward_9 = stackInfo.reward_9;
        Stacking.reward_12 = stackInfo.reward_12;

        return true;
    }

    //---------------------------------------------------------------------------------------

    //------------Anyone who is the owner of nft can call this function----------------------

    function createListing(nftData memory nftdata) public returns (bool) {
        require(
            nftdata.currency != address(0) &&
                nftdata.nftIdCollectionAddress != address(0),
            "Currency address and nftIdCollectionAddress can not be zero"
        );

        if (nftdata.nftListingType == ListingType.Sale) {
            require(
                nftdata.expiration == Expiration.months_noExpiration,
                "For nft sale there is no expiration"
            );
            require(
                nftdata.reservePricePerToken == 0,
                "For Sale there is no need for reservePricePerToken value"
            );
            require(
                nftdata.buyoutPricePerToken > 0,
                "For Sale buyoutPricePerToken can not be zero"
            );
        }

        if (nftdata.nftListingType == ListingType.Auction) {
            require(
                nftdata.startTime >= block.timestamp,
                "Start time should be greater than current time"
            );
            require(
                nftdata.endTime - nftdata.startTime > 15 minutes,
                "Difference between start time and end time should be greater than 15 minutes"
            );
            require(
                nftdata.expiration == Expiration.months_noExpiration,
                "There is no expiration. It will start and end at the given time"
            );
            require(
                nftdata.reservePricePerToken > 0,
                "Minimum bid cannot be zero"
            );

            require(
                nftdata.currency != 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
                "For Auction currency address can not be native token"
            );
        }

        if (nftdata.nftListingType == ListingType.Stacking) {
            require(
                nftdata.expiration != Expiration.months_noExpiration,
                "Stacking should be for 3, 6, 9, 12 months"
            );
            require(
                nftdata.currency != 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
                "For Stacking currency address can not be native token"
            );
            require(
                nftdata.reservePricePerToken == 0 &&
                    nftdata.buyoutPricePerToken == 0,
                "For Stacking there is no need for these values(reservePricePerToken and buyoutPricePerToken)"
            );

            if (nftdata.expiration == Expiration.months_3) {
                uint256 completeTime = block.timestamp + 3 * 2629743;
                StackingInfo[nftdata.nftIdCollectionAddress][nftdata.nftId][
                    msg.sender
                ] = stackingInfo(
                    true,
                    block.timestamp,
                    completeTime,
                    Stacking.currency,
                    Stacking.reward_3
                );
            } else if (nftdata.expiration == Expiration.months_6) {
                uint256 completeTime = block.timestamp + 6 * 2629743;
                StackingInfo[nftdata.nftIdCollectionAddress][nftdata.nftId][
                    msg.sender
                ] = stackingInfo(
                    true,
                    block.timestamp,
                    completeTime,
                    Stacking.currency,
                    Stacking.reward_6
                );
            } else if (nftdata.expiration == Expiration.months_9) {
                uint256 completeTime = block.timestamp + 9 * 2629743;
                StackingInfo[nftdata.nftIdCollectionAddress][nftdata.nftId][
                    msg.sender
                ] = stackingInfo(
                    true,
                    block.timestamp,
                    completeTime,
                    Stacking.currency,
                    Stacking.reward_9
                );
            } else if (nftdata.expiration == Expiration.months_12) {
                uint256 completeTime = block.timestamp + 12 * 2629743;
                StackingInfo[nftdata.nftIdCollectionAddress][nftdata.nftId][
                    msg.sender
                ] = stackingInfo(
                    true,
                    block.timestamp,
                    completeTime,
                    Stacking.currency,
                    Stacking.reward_12
                );
            }
        }

        nftDatasetAddress[nftdata.nftIdCollectionAddress][
            nftdata.nftId
        ] = listedNftData(
            nftdata.nftId,
            payable(msg.sender),
            nftdata.nftIdCollectionAddress,
            nftdata.currency,
            nftdata.reservePricePerToken,
            nftdata.buyoutPricePerToken,
            nftdata.startTime,
            nftdata.endTime,
            nftdata.nftListingType,
            nftdata.expiration,
            true
        );

        IERC721Upgradeable(nftdata.nftIdCollectionAddress).transferFrom(
            msg.sender,
            address(this),
            nftdata.nftId
        );

        return true;
    }

    //---------------------------------------------------------------------------------------

    function getNFTDatas(address nftCollectionAddress, uint256 _tokenId)
        private
        view
        returns (NFTData memory)
    {
        return IERC721Upgradeable(nftCollectionAddress).getNFTData(_tokenId);
    }

    function calculateFees(address nftCollectionAddress, uint256 nftId)
        private
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        NFTData memory nftDatas = getNFTDatas(nftCollectionAddress, nftId);

        uint256 buyFee = (nftDatasetAddress[nftCollectionAddress][nftId]
            .buyoutPricePerToken * platformFee) / 10000;

        uint256 _royaltyFee = (nftDatasetAddress[nftCollectionAddress][nftId]
            .buyoutPricePerToken * nftDatas.royaltyFee) / 10000;

        uint256 remainPrice = nftDatasetAddress[nftCollectionAddress][nftId]
            .buyoutPricePerToken -
            buyFee -
            _royaltyFee;

        return (buyFee, _royaltyFee, remainPrice);
    }

    function substitueTransferToHigherBidder(
        address nftCollectionAddress,
        uint256 nftId
    ) private returns (bool) {
        for (
            uint256 i = 0;
            i <
            BuyerInfo[nftCollectionAddress][nftId][
                biddingInfo[nftCollectionAddress][nftId].higherBidder
            ].index;
            i++
        ) {
            if (
                biddingInfo[nftCollectionAddress][nftId].bidderAddress[i] !=
                address(0) &&
                biddingInfo[nftCollectionAddress][nftId].bidAmount[i] != 0
            ) {
                IERC20Upgradeable(
                    nftDatasetAddress[nftCollectionAddress][nftId].currency
                ).transfer(
                        biddingInfo[nftCollectionAddress][nftId].bidderAddress[
                            i
                        ],
                        biddingInfo[nftCollectionAddress][nftId].bidAmount[i]
                    );
            }

            delete BuyerInfo[nftCollectionAddress][nftId][
                biddingInfo[nftCollectionAddress][nftId].bidderAddress[i]
            ];
        }

        return true;
    }

    //---------------------------------------------------------------------------------------

    //--------------------------------Functions For NFT Sales--------------------------------

    //---------------------------------------------------------------------------------------

    function buy(address nftCollectionAddress, uint256 nftId)
        public
        payable
        onMarketPlace(nftCollectionAddress, nftId)
        returns (bool)
    {
        require(
            nftDatasetAddress[nftCollectionAddress][nftId].nftListingType ==
                ListingType.Sale,
            "This nft is not listed for sale"
        );
        require(
            nftDatasetAddress[nftCollectionAddress][nftId].nftOwner !=
                msg.sender,
            "Nft Owner can not buy their own nft"
        );

        NFTData memory nftDatas = getNFTDatas(nftCollectionAddress, nftId);

        (
            uint256 buyFee,
            uint256 _royaltyFee,
            uint256 remainPrice
        ) = calculateFees(nftCollectionAddress, nftId);

        if (
            nftDatasetAddress[nftCollectionAddress][nftId].currency ==
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        ) {
            IERC721Upgradeable(nftCollectionAddress).transferFrom(
                address(this),
                msg.sender,
                nftId
            );

            payable(nftDatasetAddress[nftCollectionAddress][nftId].nftOwner)
                .call{value: remainPrice};

            payable(platformFeeAddress).call{value: buyFee};

            payable(nftDatas.royaltyWalletAddress).call{value: _royaltyFee};
        } else {
            IERC721Upgradeable(nftCollectionAddress).transferFrom(
                address(this),
                msg.sender,
                nftId
            );

            IERC20Upgradeable(
                nftDatasetAddress[nftCollectionAddress][nftId].currency
            ).transferFrom(
                    msg.sender,
                    nftDatasetAddress[nftCollectionAddress][nftId].nftOwner,
                    remainPrice
                );

            IERC20Upgradeable(
                nftDatasetAddress[nftCollectionAddress][nftId].currency
            ).transferFrom(msg.sender, platformFeeAddress, buyFee);

            IERC20Upgradeable(
                nftDatasetAddress[nftCollectionAddress][nftId].currency
            ).transferFrom(
                    msg.sender,
                    nftDatas.royaltyWalletAddress,
                    _royaltyFee
                );
        }

        delete nftDatasetAddress[nftCollectionAddress][nftId];
        return true;
    }

    function removeFromSale(address nftCollectionAddress, uint256 nftId)
        public
        onlyNftOwner(nftCollectionAddress, nftId)
        onMarketPlace(nftCollectionAddress, nftId)
        returns (bool)
    {
        require(
            nftDatasetAddress[nftCollectionAddress][nftId].nftListingType ==
                ListingType.Sale,
            "This nft is not listed for sale"
        );

        IERC721Upgradeable(nftCollectionAddress).transferFrom(
            address(this),
            msg.sender,
            nftId
        );

        delete nftDatasetAddress[nftCollectionAddress][nftId];

        return true;
    }

    //---------------------------------------------------------------------------------------

    //--------------------------------End Of Sale Functions----------------------------------

    //---------------------------------------------------------------------------------------

    //--------------------------------Functions For NFT Auctions-----------------------------

    //---------------------------------------------------------------------------------------

    function Bid(
        address nftCollectionAddress,
        uint256 nftId,
        uint256 _amount
    ) public payable onMarketPlace(nftCollectionAddress, nftId) returns (bool) {
        require(
            nftDatasetAddress[nftCollectionAddress][nftId].nftListingType ==
                ListingType.Auction,
            "This nft is not listed for auction"
        );
        require(
            nftDatasetAddress[nftCollectionAddress][nftId].nftOwner !=
                msg.sender,
            "Nft owner cannot make the bid for their own Nft"
        );
        require(
            nftDatasetAddress[nftCollectionAddress][nftId].startTime <=
                block.timestamp,
            "Auction for this nft not started yet"
        );

        require(
            nftDatasetAddress[nftCollectionAddress][nftId].endTime >=
                block.timestamp,
            "Auction for this nft already end"
        );

        require(
            _amount >
                nftDatasetAddress[nftCollectionAddress][nftId]
                    .reservePricePerToken ||
                _amount > biddingInfo[nftCollectionAddress][nftId].highBid,
            "Please Increase your bid"
        );

        require(
            BuyerInfo[nftCollectionAddress][nftId][msg.sender].isBidder ==
                false,
            "You already bid for this nft"
        );

        BuyerInfo[nftCollectionAddress][nftId][msg.sender] = buyerInfo(
            true,
            _amount,
            biddingInfo[nftCollectionAddress][nftId].index
        );

        biddingInfo[nftCollectionAddress][nftId].highBid = _amount;
        biddingInfo[nftCollectionAddress][nftId].higherBidder = payable(
            msg.sender
        );
        biddingInfo[nftCollectionAddress][nftId].index = biddingInfo[
            nftCollectionAddress
        ][nftId].index;
        biddingInfo[nftCollectionAddress][nftId].index++;
        biddingInfo[nftCollectionAddress][nftId].bidderAddress.push(msg.sender);
        biddingInfo[nftCollectionAddress][nftId].bidAmount.push(_amount);

        IERC20Upgradeable(
            nftDatasetAddress[nftCollectionAddress][nftId].currency
        ).transferFrom(msg.sender, address(this), _amount);

        return true;
    }

    function bidCancelByUser(address nftCollectionAddress, uint256 nftId)
        public
        onMarketPlace(nftCollectionAddress, nftId)
        returns (bool)
    {
        require(
            BuyerInfo[nftCollectionAddress][nftId][msg.sender].isBidder == true,
            "you are not the bidder, So you can not cancel bid"
        );

        IERC20Upgradeable(
            nftDatasetAddress[nftCollectionAddress][nftId].currency
        ).transfer(
                msg.sender,
                BuyerInfo[nftCollectionAddress][nftId][msg.sender].amount
            );

        biddingInfo[nftCollectionAddress][nftId].bidAmount[
            BuyerInfo[nftCollectionAddress][nftId][msg.sender].index
        ] = 0;

        biddingInfo[nftCollectionAddress][nftId].bidderAddress[
            BuyerInfo[nftCollectionAddress][nftId][msg.sender].index
        ] = address(0);

        if (
            biddingInfo[nftCollectionAddress][nftId].higherBidder == msg.sender
        ) {
            if (BuyerInfo[nftCollectionAddress][nftId][msg.sender].index == 0) {
                biddingInfo[nftCollectionAddress][nftId].higherBidder = payable(
                    address(0)
                );
                biddingInfo[nftCollectionAddress][nftId].highBid = 0;
            } else {
                uint256 i = BuyerInfo[nftCollectionAddress][nftId][msg.sender]
                    .index;

                while (
                    biddingInfo[nftCollectionAddress][nftId].bidAmount[i] == 0
                ) {
                    biddingInfo[nftCollectionAddress][nftId]
                        .higherBidder = payable(
                        biddingInfo[nftCollectionAddress][nftId].bidderAddress[
                            i - 1
                        ]
                    );
                    biddingInfo[nftCollectionAddress][nftId]
                        .highBid = biddingInfo[nftCollectionAddress][nftId]
                        .bidAmount[i - 1];
                    i--;
                }
            }
        }

        delete BuyerInfo[nftCollectionAddress][nftId][msg.sender];

        return true;
    }

    function cancelAuctionByOwner(address nftCollectionAddress, uint256 nftId)
        public
        onlyNftOwner(nftCollectionAddress, nftId)
        onMarketPlace(nftCollectionAddress, nftId)
        returns (bool)
    {
        require(
            nftDatasetAddress[nftCollectionAddress][nftId].nftListingType ==
                ListingType.Auction,
            "This nft is not listed for auction"
        );

        require(
            nftDatasetAddress[nftCollectionAddress][nftId].endTime >=
                block.timestamp,
            "Can not cancel the auction after the auction is over"
        );

        IERC721Upgradeable(nftCollectionAddress).transferFrom(
            address(this),
            msg.sender,
            nftId
        );

        for (
            uint256 i = 0;
            i < biddingInfo[nftCollectionAddress][nftId].index;
            i++
        ) {
            if (
                biddingInfo[nftCollectionAddress][nftId].bidderAddress[i] !=
                address(0) &&
                biddingInfo[nftCollectionAddress][nftId].bidAmount[i] != 0
            ) {
                IERC20Upgradeable(
                    nftDatasetAddress[nftCollectionAddress][nftId].currency
                ).transfer(
                        biddingInfo[nftCollectionAddress][nftId].bidderAddress[
                            i
                        ],
                        biddingInfo[nftCollectionAddress][nftId].bidAmount[i]
                    );
            }

            delete BuyerInfo[nftCollectionAddress][nftId][
                biddingInfo[nftCollectionAddress][nftId].bidderAddress[i]
            ];
        }

        delete biddingInfo[nftCollectionAddress][nftId];
        delete biddingInfo[nftCollectionAddress][nftId].bidderAddress;
        delete biddingInfo[nftCollectionAddress][nftId].bidAmount;
        delete nftDatasetAddress[nftCollectionAddress][nftId];

        return true;
    }

    function tranferToHigherBidder(address nftCollectionAddress, uint256 nftId)
        public
        onlyNftOwner(nftCollectionAddress, nftId)
        onMarketPlace(nftCollectionAddress, nftId)
        returns (bool)
    {
        require(
            nftDatasetAddress[nftCollectionAddress][nftId].nftListingType ==
                ListingType.Auction,
            "This nft is not listed for auction"
        );

        require(
            nftDatasetAddress[nftCollectionAddress][nftId].endTime <=
                block.timestamp,
            "Can not transfer the NFT before the auction ends"
        );

        if (biddingInfo[nftCollectionAddress][nftId].highBid == 0) {
            IERC721Upgradeable(nftCollectionAddress).transferFrom(
                address(this),
                msg.sender,
                nftId
            );
        } else {
            NFTData memory nftDatas = getNFTDatas(nftCollectionAddress, nftId);
            (
                uint256 buyFee,
                uint256 _royaltyFee,
                uint256 remainPrice
            ) = calculateFees(nftCollectionAddress, nftId);

            IERC721Upgradeable(nftCollectionAddress).transferFrom(
                address(this),
                biddingInfo[nftCollectionAddress][nftId].higherBidder,
                nftId
            );

            IERC20Upgradeable(
                nftDatasetAddress[nftCollectionAddress][nftId].currency
            ).transfer(platformFeeAddress, buyFee);

            IERC20Upgradeable(
                nftDatasetAddress[nftCollectionAddress][nftId].currency
            ).transfer(
                    nftDatasetAddress[nftCollectionAddress][nftId].nftOwner,
                    remainPrice
                );

            IERC20Upgradeable(
                nftDatasetAddress[nftCollectionAddress][nftId].currency
            ).transfer(nftDatas.royaltyWalletAddress, _royaltyFee);

            substitueTransferToHigherBidder(nftCollectionAddress, nftId);
        }

        delete nftDatasetAddress[nftCollectionAddress][nftId];
        delete biddingInfo[nftCollectionAddress][nftId];

        return true;
    }

    function noOfBidders(address nftCollectionAddress, uint256 nftId)
        public
        view
        onMarketPlace(nftCollectionAddress, nftId)
        returns (
            uint256,
            address[] memory bidderAddress,
            uint256[] memory bidAmount
        )
    {
        require(
            nftDatasetAddress[nftCollectionAddress][nftId].nftListingType ==
                ListingType.Auction,
            "This nft is not listed for auction"
        );

        return (
            biddingInfo[nftCollectionAddress][nftId].bidderAddress.length,
            biddingInfo[nftCollectionAddress][nftId].bidderAddress,
            biddingInfo[nftCollectionAddress][nftId].bidAmount
        );
    }

    //---------------------------------------------------------------------------------------

    //-------------------------End Of Auction Functions--------------------------------------

    //---------------------------------------------------------------------------------------

    //-------------------------Functions For NFT Stacking------------------------------------

    function unStacking(address nftCollectionAddress, uint256 nftId)
        public
        onlyNftOwner(nftCollectionAddress, nftId)
        onMarketPlace(nftCollectionAddress, nftId)
        returns (bool)
    {
        require(
            nftDatasetAddress[nftCollectionAddress][nftId].nftListingType ==
                ListingType.Stacking,
            "This nft is not listed for stacking"
        );

        require(
            StackingInfo[nftCollectionAddress][nftId][msg.sender]
                .completeTime <= block.timestamp,
            "Your stacking period is not completed yet"
        );

        IERC20Upgradeable(
            StackingInfo[nftCollectionAddress][nftId][msg.sender].currency
        ).transfer(
                nftDatasetAddress[nftCollectionAddress][nftId].nftOwner,
                StackingInfo[nftCollectionAddress][nftId][msg.sender].reward
            );

        IERC721Upgradeable(nftCollectionAddress).transferFrom(
            address(this),
            msg.sender,
            nftId
        );

        delete nftDatasetAddress[nftCollectionAddress][nftId];
        delete StackingInfo[nftCollectionAddress][nftId][msg.sender];

        return true;
    }
}

//[0,"0xcbbB3cc3322A5Ec00140A97fc4Fe439d7975Ae60","0x2c107A32BC809C474f940faB0e189d35175Ad1C5",0,1000,0,0,0,0]
//[0,"0xD7ACd2a9FD159E69Bb102A1ca21C9a3e3A5F771B","0xd9145CCE52D386f254917e481eB44e9943F39138",100,0,1675312800,1675314000,1,0]
