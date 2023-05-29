// SPDX-License-Identifier: MIT

import "erc721a/contracts/extensions/ERC721AQueryable.sol";
import "@divergencetech/ethier/contracts/erc721/BaseTokenURI.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol"; //@audit - used for `Strings`
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

pragma solidity ^0.8.6; //@audit - floating pragma

contract WhitelightNFT is ERC721AQueryable, BaseTokenURI, ReentrancyGuard {
    using Strings for uint256; //@audit - why?

    uint256 public totalCollectedFunds;
    uint256 public mintPrice;
    //@audit - init distribution in contructor
    uint256 public distribution1Percentage = 500;
    uint256 public distribution2Percentage = 500;
    //@audit - init addresses in constructor
    address public distribution1address =
        0x8ba4c8705905522b0A89D5eA597E33ec1F828035;
    address public distribution2address =
        0x8464bFa0d5aB3D91CFB401E77EfDE5158dCeE48f;

    //@audit - move to top of contract storage
    uint256 public constant FEE_DENOMINATOR = 1000; //@audit - precision - look into mul before div
    uint256 public constant MAX_SUPPLY = 575;

    mapping(address => uint256) public withdrewAmount;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _initBaseURI,
        uint256 _mintPrice
    ) ERC721A(_name, _symbol) BaseTokenURI(_initBaseURI) {
        require(_mintPrice > 0, "Mint price must be greater than 0");
        mintPrice = _mintPrice;
    }

    receive() external payable {} //@audit money not withdrawable as not added to `totalCollected`

    function _startTokenId() internal pure override returns (uint256) {
        //@audit - start at 0 or 1? 1 because hashlips starts at 1.
        return 1;
    }

    function _baseURI()
        internal
        view
        override(BaseTokenURI, ERC721A)
        returns (string memory)
    {
        //@audit - have to override to set baseURI for ERC721A contract
        return BaseTokenURI._baseURI();
    }

    function mint(uint256 _mintAmount) external payable {
        require(_mintAmount > 0, "Amount to mint can not be 0"); //@audit - gas savings on !=
        require(
            totalSupply() + _mintAmount <= MAX_SUPPLY,
            "Cannot mint more than max supply"
        );
        require(
            msg.value >= mintPrice * _mintAmount,
            "Amount sent less than the cost of minting NFT(s)"
        );
        _safeMint(_msgSender(), _mintAmount);

        uint256 costNative = _mintAmount * mintPrice;
        uint256 excessNative = msg.value - costNative;

        totalCollectedFunds += costNative;

        if (msg.value > costNative) {
            (bool success, ) = address(_msgSender()).call{value: excessNative}(
                ""
            );
            require(success, "Unable to refund excess ether"); //@audit - unable to refund and unable to withdraw. Only `totalCollectedFunds` are withdrawable, not `excess`.
        }
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721Metadata: tokenURI queried for nonexistent token"
        );
        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        tokenId.toString(),
                        ".json" //@audit - function overriden only to add ".json" - necessary?
                    )
                )
                : "";
    }

    function setMintPrice(uint256 _mintPrice) external onlyOwner {
        //@audit - never import ownable?
        mintPrice = _mintPrice;
    }

    function setDistribution1address(
        address _distribution1address
    ) public onlyOwner {
        withdrewAmount[_distribution1address] = withdrewAmount[
            distribution1address
        ];
        delete withdrewAmount[distribution1address];

        distribution1address = _distribution1address;
    }

    function setDistribution2address(
        address _distribution2address
    ) public onlyOwner {
        // @audit - address is not checked for address 0
        withdrewAmount[_distribution2address] = withdrewAmount[
            distribution2address
        ];
        delete withdrewAmount[distribution2address];

        distribution2address = _distribution2address;
    }

    function configure(
        uint256 _mintPrice,
        address _distribution1address,
        address _distribution2address
    ) external onlyOwner {
        mintPrice = _mintPrice;
        setDistribution1address(_distribution1address);
        setDistribution2address(_distribution2address);
    }

    function getAvailableAmount(
        address _address
    ) public view returns (uint256) {
        //@audit - anyone can call and be told they are owed the funds of dist2 - very low can be private
        uint256 percentage = _address == distribution1address
            ? distribution1Percentage
            : distribution2Percentage;
        uint256 ownedAmount = (totalCollectedFunds * percentage) /
            FEE_DENOMINATOR;
        uint256 availableAmount = ownedAmount - withdrewAmount[_address];
        return availableAmount;
    }

    function withdraw() external onlyOwner nonReentrant {
        _withdraw(distribution1address);
        _withdraw(distribution2address);
    }

    function _withdraw(address _to) private {
        uint256 availableAmount = getAvailableAmount(_to);
        require(availableAmount > 0, "No funds to claim");

        withdrewAmount[_to] += availableAmount;

        (bool success, ) = _to.call{value: availableAmount}("");
        require(success, "Unable to distribute address funds");
    }
}