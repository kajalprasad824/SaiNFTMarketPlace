// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./NotUpgradableCollection.sol";

contract MyToken is ERC721, ERC721URIStorage, ERC721Burnable, Ownable, EIP712 {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    string private constant SIGNING_DOMAIN = "LazyNFT-Voucher";
    string private constant SIGNATURE_VERSION = "1";

    address payable platformFeeAddress;
    uint256 platformFee;

    struct NFTData {
        string uri;
        uint256 royaltyFee;
        address royaltyWalletAddress;
        address nftCreator;
    }
    mapping(uint256 => NFTData) public storeData;

    struct NFTVoucher {
        address nftCreator;
        uint256 minPrice;
        uint256 royaltyFee;
        address royaltyWalletAddress;
        string uri;
        address currency;
    }

    constructor(address _platformFeeAddress, uint256 _platformFee)
        ERC721("KajalNFT", "Kajal")
        EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION)
    {
        platformFeeAddress = payable(_platformFeeAddress);
        platformFee = _platformFee;
    }

    function safeMint(address to, string memory uri) public {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    modifier NFTOwner(uint256 tokenIdCounter) {
        require(
            ownerOf(tokenIdCounter) == msg.sender,
            "You are not the Owner of this NFT"
        );
        _;
    }

    modifier NFTCreator(uint256 tokenIdCounter) {
        require(
            storeData[tokenIdCounter].nftCreator == msg.sender,
            "You are not the Creator of this NFT"
        );
        _;
    }

    function directMint(
        address to,
        string memory _uri,
        uint256 _royaltyFee,
        address _royaltyWalletAddress
    ) public returns (bool) {
        require(to != address(0), "Cannot mint nft to zeroth address");
        uint256 tokenIdCounter = _tokenIdCounter.current();

        storeData[tokenIdCounter].uri = _uri;
        storeData[tokenIdCounter].royaltyFee = _royaltyFee;
        storeData[tokenIdCounter].royaltyWalletAddress = _royaltyWalletAddress;
        storeData[tokenIdCounter].nftCreator = msg.sender;

        _safeMint(to, tokenIdCounter);
        _setTokenURI(tokenIdCounter, _uri);

        _tokenIdCounter.increment();

        return true;
    }

    function getPlatformFeeDetails() public view returns (uint256, address) {
        return (platformFee, platformFeeAddress);
    }

    //nft owner can burn nft via this function
    function burnNFT(uint256 tokenIdCounter) public NFTOwner(tokenIdCounter) {
        storeData[tokenIdCounter] = NFTData("", 0, address(0), address(0));
        burn(tokenIdCounter);
    }

    function updateNFTUriData(uint256 tokenIdCounter, string memory _uri)
        public
        NFTOwner(tokenIdCounter)
    {
        storeData[tokenIdCounter].uri = _uri;
    }

    function setPlatformFee(uint256 _platformFee, address _platformFeeAddress)
        public
        onlyOwner
    {
        platformFee = _platformFee;
        platformFeeAddress = payable(_platformFeeAddress);
    }

    function getTotalNFTCount() public view returns (uint256) {
        return _tokenIdCounter.current();
    }

    function redeem(NFTVoucher calldata voucher, bytes memory _signature)
        public
        payable
        returns (uint256)
    {
        address signer = _verify(voucher, _signature);

        require(msg.value >= voucher.minPrice, "Insufficient funds to redeem");
        uint256 _royaltyFee = (msg.value * voucher.royaltyFee) / 10000;
        uint256 _platformFee = (msg.value * platformFee) / 10000;
        uint256 _sellerAmount = msg.value - _royaltyFee - _platformFee;

        if (voucher.currency == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            payable(voucher.royaltyWalletAddress).transfer(_royaltyFee);
            payable(platformFeeAddress).transfer(_platformFee);
            payable(voucher.nftCreator).transfer(_sellerAmount);
        } else {
            IERC20(voucher.currency).transferFrom(
                msg.sender,
                voucher.royaltyWalletAddress,
                _royaltyFee
            );
            IERC20(voucher.currency).transferFrom(
                msg.sender,
                platformFeeAddress,
                _platformFee
            );
            IERC20(voucher.currency).transferFrom(
                msg.sender,
                voucher.nftCreator,
                _sellerAmount
            );
        }

        uint256 tokenIdCounter = _tokenIdCounter.current();
        _mint(signer, tokenIdCounter);
        _setTokenURI(tokenIdCounter, voucher.uri);

        _transfer(signer, msg.sender, tokenIdCounter);

        storeData[tokenIdCounter].uri = voucher.uri;
        storeData[tokenIdCounter].royaltyFee = voucher.royaltyFee;
        storeData[tokenIdCounter].royaltyWalletAddress = voucher
            .royaltyWalletAddress;
        storeData[tokenIdCounter].nftCreator = voucher.nftCreator;

        _tokenIdCounter.increment();

        return tokenIdCounter;
    }

    function _hash(NFTVoucher calldata voucher)
        internal
        view
        returns (bytes32)
    {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "NFTVoucher(address nftCreator,uint256 minPrice,uint royaltyFee,address royaltyWalletAddress,string uri,address currency)"
                        ),
                        voucher.nftCreator,
                        voucher.minPrice,
                        voucher.royaltyFee,
                        voucher.royaltyWalletAddress,
                        keccak256(bytes(voucher.uri)),
                        voucher.currency
                    )
                )
            );
    }

    function getChainID() external view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    function _verify(NFTVoucher calldata voucher, bytes memory _signature)
        public
        view
        returns (address)
    {
        bytes32 digest = _hash(voucher);
        return ECDSA.recover(digest, _signature);
    }

    function getNFTData(uint256 _tokenId) public view returns (NFTData memory) {
        return storeData[_tokenId];
    }
}
